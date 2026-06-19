using System.Collections.Generic;
using System.IO;
using UnityEngine;

public class TerrainGenerator : MonoBehaviour {

    public bool printTimers;

    [Header ("Mesh Settings")]
    public int mapSize = 255;
    public float scale = 20;
    public float elevationScale = 10;
    public Material material;

    [Header ("Erosion Settings")]
    public ComputeShader erosion;
    public int numErosionIterations = 50000;
    public int erosionBrushRadius = 3;

    public int maxLifetime = 30;
    public float sedimentCapacityFactor = 3;
    public float minSedimentCapacity = .01f;
    public float depositSpeed = 0.3f;
    public float erodeSpeed = 0.3f;

    public float evaporateSpeed = .01f;
    public float gravity = 4;
    public float startSpeed = 1;
    public float startWater = 1;
    [Range (0, 1)]
    public float inertia = 0.3f;

    [Header("Erosion Settings")]
    [Range(0, 90)]
    public int talusAngle = 45;
    public int thermalIterations = 10;
    [Range(0, 0.45f)]
    public float thermalRate = 0.4f;
    public bool thermalErosion = true;


    [Header("Export Settings")]
    public string path = Application.dataPath;
    public string filename = "heightmap1";

    // Internal
    float[] map;
    Mesh mesh;
    int mapSizeWithBorder;

    MeshRenderer meshRenderer;
    MeshFilter meshFilter;

    public void GenerateHeightMap () {
        mapSizeWithBorder = mapSize + erosionBrushRadius * 2;
        map = FindFirstObjectByType<HeightMapGenerator>().GenerateHeightMap(mapSizeWithBorder);
    }

    public void Erode () {
        int hydraulicKernel = erosion.FindKernel("CSMain");
        int thermalKernel = erosion.FindKernel("ThermalErode");

        int numThreads = numErosionIterations / 1024;

        // Create brush
        List<int> brushIndexOffsets = new List<int> ();
        List<float> brushWeights = new List<float> ();

        float weightSum = 0;
        for (int brushY = -erosionBrushRadius; brushY <= erosionBrushRadius; brushY++) {
            for (int brushX = -erosionBrushRadius; brushX <= erosionBrushRadius; brushX++) {
                float sqrDst = brushX * brushX + brushY * brushY;
                if (sqrDst < erosionBrushRadius * erosionBrushRadius) {
                    brushIndexOffsets.Add (brushY * mapSize + brushX);
                    float brushWeight = 1 - Mathf.Sqrt (sqrDst) / erosionBrushRadius;
                    weightSum += brushWeight;
                    brushWeights.Add (brushWeight);
                }
            }
        }
        for (int i = 0; i < brushWeights.Count; i++) {
            brushWeights[i] /= weightSum;
        }

        // Send brush data to compute shader
        ComputeBuffer brushIndexBuffer = new ComputeBuffer (brushIndexOffsets.Count, sizeof (int));
        ComputeBuffer brushWeightBuffer = new ComputeBuffer (brushWeights.Count, sizeof (int));
        brushIndexBuffer.SetData (brushIndexOffsets);
        brushWeightBuffer.SetData (brushWeights);
        erosion.SetBuffer (0, "brushIndices", brushIndexBuffer);
        erosion.SetBuffer (0, "brushWeights", brushWeightBuffer);

        // Generate random indices for droplet placement
        int[] randomIndices = new int[numErosionIterations];
        for (int i = 0; i < numErosionIterations; i++) {
            int randomX = Random.Range (erosionBrushRadius, mapSize + erosionBrushRadius);
            int randomY = Random.Range (erosionBrushRadius, mapSize + erosionBrushRadius);
            randomIndices[i] = randomY * mapSize + randomX;
        }

        // Send random indices to compute shader
        ComputeBuffer randomIndexBuffer = new ComputeBuffer (randomIndices.Length, sizeof (int));
        randomIndexBuffer.SetData (randomIndices);
        erosion.SetBuffer (0, "randomIndices", randomIndexBuffer);

        // Heightmap buffer
        ComputeBuffer mapBuffer = new ComputeBuffer (map.Length, sizeof (float));
        ComputeBuffer mapOutBuffer = new ComputeBuffer(map.Length, sizeof(float));
        mapBuffer.SetData (map);
        mapOutBuffer.SetData (map);
        erosion.SetBuffer (0, "map", mapBuffer);
        erosion.SetBuffer(thermalKernel, "map", mapBuffer);

        // Settings
        erosion.SetInt ("borderSize", erosionBrushRadius);
        erosion.SetInt ("mapSize", mapSizeWithBorder);
        erosion.SetInt ("brushLength", brushIndexOffsets.Count);
        erosion.SetInt ("maxLifetime", maxLifetime);
        erosion.SetFloat ("inertia", inertia);
        erosion.SetFloat ("sedimentCapacityFactor", sedimentCapacityFactor);
        erosion.SetFloat ("minSedimentCapacity", minSedimentCapacity);
        erosion.SetFloat ("depositSpeed", depositSpeed);
        erosion.SetFloat ("erodeSpeed", erodeSpeed);
        erosion.SetFloat ("evaporateSpeed", evaporateSpeed);
        erosion.SetFloat ("gravity", gravity);
        erosion.SetFloat ("startSpeed", startSpeed);
        erosion.SetFloat ("startWater", startWater);

        erosion.SetInt ("talusAngle", talusAngle);
        erosion.SetFloat("cellAspect", (2 * scale / mapSize) / elevationScale);  
        erosion.SetFloat("thermalRate", thermalRate);  

        int intervals = 10;
        int groups = Mathf.CeilToInt(mapSizeWithBorder / 8f);

        for (int i = 0; i < intervals; i++)
        {
            // thermal pass
            if (thermalErosion)
            {
                for (int j = 0; j < thermalIterations; j++)
                {
                    erosion.SetBuffer(thermalKernel, "map", mapBuffer);
                    erosion.SetBuffer(thermalKernel, "mapOut", mapOutBuffer);
                    erosion.Dispatch(thermalKernel, groups, groups, 1);

                    (mapBuffer, mapOutBuffer) = (mapOutBuffer, mapBuffer);
                }
            }
            // hydraulic pass
            erosion.SetBuffer(hydraulicKernel, "map", mapBuffer);
            erosion.Dispatch(hydraulicKernel, numThreads / intervals, 1, 1);
        }

        mapBuffer.GetData(map);

        mapBuffer.GetData(map);

        // Release buffers
        mapBuffer.Release ();
        mapOutBuffer?.Release ();
        randomIndexBuffer.Release ();
        brushIndexBuffer.Release ();
        brushWeightBuffer.Release ();
    }

    public void ContructMesh () {
        Vector3[] verts = new Vector3[mapSize * mapSize];
        int[] triangles = new int[(mapSize - 1) * (mapSize - 1) * 6];
        int t = 0;

        for (int i = 0; i < mapSize * mapSize; i++) {
            int x = i % mapSize;
            int y = i / mapSize;
            int borderedMapIndex = (y + erosionBrushRadius) * mapSizeWithBorder + x + erosionBrushRadius;
            int meshMapIndex = y * mapSize + x;

            Vector2 percent = new Vector2 (x / (mapSize - 1f), y / (mapSize - 1f));
            Vector3 pos = new Vector3 (percent.x * 2 - 1, 0, percent.y * 2 - 1) * scale;

            float normalizedHeight = map[borderedMapIndex];
            pos += Vector3.up * normalizedHeight * elevationScale;
            verts[meshMapIndex] = pos;

            // Construct triangles
            if (x != mapSize - 1 && y != mapSize - 1) {
                t = (y * (mapSize - 1) + x) * 3 * 2;

                triangles[t + 0] = meshMapIndex + mapSize;
                triangles[t + 1] = meshMapIndex + mapSize + 1;
                triangles[t + 2] = meshMapIndex;

                triangles[t + 3] = meshMapIndex + mapSize + 1;
                triangles[t + 4] = meshMapIndex + 1;
                triangles[t + 5] = meshMapIndex;
                t += 6;
            }
        }

        if (mesh == null) {
            mesh = new Mesh ();
        } else {
            mesh.Clear ();
        }
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.vertices = verts;
        mesh.triangles = triangles;
        mesh.RecalculateNormals ();

        AssignMeshComponents ();
        meshFilter.sharedMesh = mesh;
        meshRenderer.sharedMaterial = material;

        material.SetFloat ("_MaxHeight", elevationScale);
    }

    void AssignMeshComponents () {
        // Find/creator mesh holder object in children
        string meshHolderName = "Mesh Holder";
        Transform meshHolder = transform.Find (meshHolderName);
        if (meshHolder == null) {
            meshHolder = new GameObject (meshHolderName).transform;
            meshHolder.transform.parent = transform;
            meshHolder.transform.localPosition = Vector3.zero;
            meshHolder.transform.localRotation = Quaternion.identity;
        }

        // Ensure mesh renderer and filter components are assigned
        if (!meshHolder.gameObject.GetComponent<MeshFilter> ()) {
            meshHolder.gameObject.AddComponent<MeshFilter> ();
        }
        if (!meshHolder.GetComponent<MeshRenderer> ()) {
            meshHolder.gameObject.AddComponent<MeshRenderer> ();
        }

        meshRenderer = meshHolder.GetComponent<MeshRenderer> ();
        meshFilter = meshHolder.GetComponent<MeshFilter> ();
    }

    public void SaveToPNG()
    {
        int border = (mapSizeWithBorder - mapSize) / 2;

        Texture2D texture = new Texture2D(mapSize, mapSize, TextureFormat.R8, false);
        Color[] colors = new Color[mapSize * mapSize];

        for (int y = 0; y < mapSize; y++)
        {
            for (int x = 0; x < mapSize; x++)
            {
                int srcIndex = (y + border) * mapSizeWithBorder + (x + border);
                int dstIndex = y * mapSize + x;
                float h = map[srcIndex];
                colors[dstIndex] = new Color(h, 0, 0);
            }
        }

        texture.SetPixels(colors);
        texture.Apply();

        byte[] bytes = texture.EncodeToPNG();
        File.WriteAllBytes($"{path}/{filename}.png", bytes);
        Debug.Log($"Saved to: {path}/{filename}.png");
    }
}