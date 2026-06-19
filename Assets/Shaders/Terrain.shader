Shader "Custom/Terrain" {
    Properties {
        [Header(Colours)]
        _SnowColour ("Snow Colour", Color) = (1,1,1,1)
        _GrassColour ("Grass Colour", Color) = (0.2,0.6,0.1,1)
        _RockColour ("Rock Colour", Color) = (0.4,0.35,0.3,1)
        _SandColour ("Sand Colour", Color) = (0.76,0.7,0.5,1)

        [Header(Textures)]
        _GrassTex ("Grass Texture", 2D) = "white" {}
        _RockTex ("Rock Texture", 2D) = "white" {}
        _SnowTex ("Snow Texture", 2D) = "white" {}
        _SandTex ("Sand Texture", 2D) = "white" {}
        _TextureScale ("Texture Scale", Float) = 10

        [Header(Height Thresholds)]
        _MaxHeight ("Max Height", Float) = 10
        _SnowHeight ("Snow Start Height", Range(0,1)) = 0.8
        _SandHeight ("Sand End Height", Range(0,1)) = 0.15
        _HeightBlend ("Height Blend", Range(0,0.3)) = 0.05

        [Header(Snow)]
        _SnowNoiseScale ("Snow Noise Scale", Float) = 5
        _SnowNoiseStrength ("Snow Noise Strength", Range(0, 0.3)) = 0.1
        _SnowSmoothness ("Snow Smoothness", Range(0,1)) = 0.6
        _SnowNormalBlend ("Snow Normal Blend", Range(0,1)) = 0.3

        [Header(Slope)]
        _GrassSlopeThreshold ("Grass Slope Threshold", Range(0,1)) = 0.4
        _GrassBlendAmount ("Grass Blend Amount", Range(0,1)) = 0.3

        [Header(PBR)]
        _GrassSmoothness ("Grass Smoothness", Range(0,1)) = 0.1
        _RockSmoothness ("Rock Smoothness", Range(0,1)) = 0.15
        _SandSmoothness ("Sand Smoothness", Range(0,1)) = 0.05
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        CGPROGRAM
        #pragma surface surf Standard fullforwardshadows
        #pragma target 3.0

        struct Input {
            float3 worldPos;
            float3 worldNormal;
            INTERNAL_DATA
        };

        half _MaxHeight;
        half _GrassSlopeThreshold;
        half _GrassBlendAmount;
        half _SnowHeight;
        half _SandHeight;
        half _HeightBlend;
        half _TextureScale;
        half _SnowNoiseScale;
        half _SnowNoiseStrength;
        half _SnowSmoothness;
        half _SnowNormalBlend;
        half _GrassSmoothness;
        half _RockSmoothness;
        half _SandSmoothness;

        fixed4 _GrassColour;
        fixed4 _RockColour;
        fixed4 _SnowColour;
        fixed4 _SandColour;

        sampler2D _GrassTex;
        sampler2D _RockTex;
        sampler2D _SnowTex;
        sampler2D _SandTex;

        // Einfaches Value Noise fuer unregelmässigen Schnee
        float hash(float2 p) {
            return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        float noise(float2 p) {
            float2 i = floor(p);
            float2 f = frac(p);
            float2 u = f * f * (3.0 - 2.0 * f); // smoothstep

            return lerp(
                lerp(hash(i + float2(0,0)), hash(i + float2(1,0)), u.x),
                lerp(hash(i + float2(0,1)), hash(i + float2(1,1)), u.x),
                u.y
            );
        }

        // Mehrere Noise-Oktaven fuer natuerlicheres Aussehen
        float fbmNoise(float2 p) {
            float value = 0;
            float amplitude = 0.5;
            float frequency = 1.0;
            for (int i = 0; i < 4; i++) {
                value += noise(p * frequency) * amplitude;
                amplitude *= 0.5;
                frequency *= 2.0;
            }
            return value;
        }

        fixed4 triplanar(sampler2D tex, float3 worldPos, float3 worldNormal, float scale)
        {
            float3 blendWeights = abs(worldNormal);
            blendWeights = pow(blendWeights, 4);
            blendWeights /= (blendWeights.x + blendWeights.y + blendWeights.z);

            fixed4 xProj = tex2D(tex, worldPos.yz / scale);
            fixed4 yProj = tex2D(tex, worldPos.xz / scale);
            fixed4 zProj = tex2D(tex, worldPos.xy / scale);

            return xProj * blendWeights.x + yProj * blendWeights.y + zProj * blendWeights.z;
        }

        void surf (Input IN, inout SurfaceOutputStandard o) {
            float height = IN.worldPos.y / _MaxHeight;
            float slope = 1 - IN.worldNormal.y;

            // Noise verschiebt die Schnee-Grenze unregelmässig
            float snowNoise = fbmNoise(IN.worldPos.xz / _SnowNoiseScale);
            float noisySnowHeight = _SnowHeight - snowNoise * _SnowNoiseStrength;

            // Schnee mag auch flache Bereiche mehr als steile
            float slopeFactor = 1 - saturate(slope / 0.5);
            noisySnowHeight = lerp(noisySnowHeight + 0.1, noisySnowHeight, slopeFactor);

            // --- Gewichte ---
            float snowWeight = saturate((height - (noisySnowHeight - _HeightBlend)) / (_HeightBlend * 2));
            float sandWeight = saturate((_SandHeight - height + _HeightBlend) / (_HeightBlend * 2));

            float grassBlendHeight = _GrassSlopeThreshold * (1 - _GrassBlendAmount);
            float grassWeight = 1 - saturate((slope - grassBlendHeight) / (_GrassSlopeThreshold - grassBlendHeight));
            grassWeight *= (1 - snowWeight) * (1 - sandWeight);

            float rockWeight = (1 - grassWeight) * (1 - snowWeight) * (1 - sandWeight);

            // --- Texturen ---
            fixed4 grassTex = triplanar(_GrassTex, IN.worldPos, IN.worldNormal, _TextureScale) * _GrassColour;
            fixed4 rockTex  = triplanar(_RockTex,  IN.worldPos, IN.worldNormal, _TextureScale) * _RockColour;
            fixed4 snowTex  = triplanar(_SnowTex,  IN.worldPos, IN.worldNormal, _TextureScale) * _SnowColour;
            fixed4 sandTex  = triplanar(_SandTex,  IN.worldPos, IN.worldNormal, _TextureScale) * _SandColour;

            o.Albedo = grassTex * grassWeight
                     + rockTex  * rockWeight
                     + snowTex  * snowWeight
                     + sandTex  * sandWeight;

            // --- PBR: Smoothness pro Material ---
            o.Smoothness = _GrassSmoothness * grassWeight
                         + _RockSmoothness  * rockWeight
                         + _SnowSmoothness  * snowWeight
                         + _SandSmoothness  * sandWeight;

            o.Metallic = 0;

        }
        ENDCG
    }
}