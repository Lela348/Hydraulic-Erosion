Shader "Custom/Water" {
    Properties {
        _ShallowColour ("Shallow Colour", Color) = (0.2, 0.6, 0.8, 0.6)
        _DeepColour ("Deep Colour", Color) = (0.05, 0.2, 0.5, 0.9)
        _DepthMaxDistance ("Depth Distance", Float) = 2

        [Header(Waves)]
        _WaveSpeed ("Wave Speed", Float) = 0.5
        _WaveStrength ("Wave Strength", Range(0, 0.1)) = 0.02
        _WaveScale ("Wave Scale", Float) = 15

        _WaveSpeed2 ("Wave Speed 2", Float) = 0.3
        _WaveStrength2 ("Wave Strength 2", Range(0, 0.1)) = 0.015
        _WaveScale2 ("Wave Scale 2", Float) = 23

        [Header(Surface)]
        _Smoothness ("Smoothness", Range(0,1)) = 0.92
        _FresnelPower ("Fresnel Power", Range(0.1, 5)) = 2
        _FoamDistance ("Foam Distance", Float) = 0.3
        _FoamColour ("Foam Colour", Color) = (1,1,1,1)
    }

    SubShader {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        GrabPass { "_BackgroundTexture" }

        CGPROGRAM
        #pragma surface surf Standard alpha:fade vertex:vert
        #pragma target 3.0

        #include "UnityCG.cginc"

        sampler2D _CameraDepthTexture;
        sampler2D _BackgroundTexture;

        fixed4 _ShallowColour;
        fixed4 _DeepColour;
        fixed4 _FoamColour;
        float _DepthMaxDistance;
        float _WaveSpeed;
        float _WaveStrength;
        float _WaveScale;
        float _WaveSpeed2;
        float _WaveStrength2;
        float _WaveScale2;
        float _Smoothness;
        float _FresnelPower;
        float _FoamDistance;

        struct Input {
            float3 worldPos;
            float3 worldNormal;
            float3 viewDir;
            float4 screenPos;
            INTERNAL_DATA
        };

        // Einfaches Noise fuer Wellenform
        float hash(float2 p) {
            return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        float smoothNoise(float2 p) {
            float2 i = floor(p);
            float2 f = frac(p);
            float2 u = f * f * (3.0 - 2.0 * f);
            return lerp(
                lerp(hash(i), hash(i + float2(1,0)), u.x),
                lerp(hash(i + float2(0,1)), hash(i + float2(1,1)), u.x),
                u.y
            );
        }

        // Gibt Wellenhoehe zurueck
        float waveHeight(float2 pos, float scale, float speed, float strength) {
            float t = _Time.y * speed;
            float w1 = smoothNoise(pos / scale + float2(t, t * 0.7));
            float w2 = smoothNoise(pos / scale * 1.7 + float2(-t * 0.8, t * 0.6));
            return (w1 + w2 - 1.0) * strength;
        }

        // Vertex-Displacement fuer Wellenanimation
        void vert(inout appdata_full v) {
            float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
            float wave = waveHeight(worldPos.xz, _WaveScale, _WaveSpeed, _WaveStrength)
                       + waveHeight(worldPos.xz, _WaveScale2, _WaveSpeed2, _WaveStrength2);
            v.vertex.y += wave;
        }

        void surf(Input IN, inout SurfaceOutputStandard o) {
            // --- Tiefenbasierte Farbe ---
            float depth = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(IN.screenPos)).r);
            float waterDepth = depth - IN.screenPos.w;
            float depthFade = saturate(waterDepth / _DepthMaxDistance);

            fixed4 waterColour = lerp(_ShallowColour, _DeepColour, depthFade);

            // --- Schaum an Ufern ---
            float foam = 1 - saturate(waterDepth / _FoamDistance);
            // Schaum etwas unregelmässig machen
            float foamNoise = smoothNoise(IN.worldPos.xz * 3 + _Time.y * 0.3);
            foam = saturate(foam - foamNoise * 0.3);

            // --- Fresnel: flacher Winkel = mehr Reflexion ---
            float fresnel = pow(1 - saturate(dot(IN.viewDir, WorldNormalVector(IN, o.Normal))), _FresnelPower);

            // --- Finale Farbe ---
            o.Albedo = lerp(waterColour.rgb, _FoamColour.rgb, foam);
            o.Smoothness = _Smoothness * (1 - foam * 0.5);
            o.Metallic = 0;
            o.Alpha = lerp(waterColour.a, 1, foam + fresnel * 0.3);
        }
        ENDCG
    }
}