Shader "Unlit/CartoonWater"
{
    Properties
    {
        [Header(Water Colors)]
        _WaterSurfaceColor("Water Surface Color", Color) = (1, 1, 1, 1)
        _WaterDeepColor("Water Deep Color", Color) = (1, 1, 1, 1)
        _WaterShoreColor("Water Shore Color", Color) = (1, 1, 1, 1)
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0

        [Header(Water Normal Map)]
        [Normal]_NormalTex("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0, 1)) = 0
        _NormalSpeed("Normal Speed", Vector) = (0, 0, 0, 0)
        
        [Header(World Reflection)]
        _WorldReflectionStrength("Reflection Strength", Range(0, 1)) = 0

        [Header(Thresholds)]
        _NearShoreThreshold("Near Shore Threshold", Float) = 0
        _DeepThreshold("Deep Threshold", Float) = 0
        
        [Header(Refraction)]
        _DistortionTex("Distortion Texture", 2D) = "bump" {}
        _DistortionAmount("Distortion Amount", Float) = 0
        _DistortionSpeed("Distortion Speed", Vector) = (0.1, 0.1, 0, 0)

        [Header(Displacement)]
        _DisplacementTex("Displacement Texture", 2D) = "white" {}
        _DisplacementAmount("Displacement Amount", Float) = 0
        _DisplacementSpeed("Displacement Speed", Vector) = (0.1, 0.1, 0, 0)

        [Header(Foam)]
        _FoamTex("Foam Texture", 2D) = "white" {}
        _FoamCutoff("Foam Cutoff", Range(0, 1)) = 0.777
        _FoamSpeed("Foam Speed", Vector) = (0, 0, 0, 0)
        _FoamDistance("Foam Distance", Float) = 0.4
        _FoamDistortionTex("Foam Distortion", 2D) = "white" {}
        _FoamDistortionAmount("Foam Distortion Amount", Range(0, 1)) = 0.27
        
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent"}
        Cull Off
        ZWrite Off
        LOD 200

        //Get grab pass information and store into _GrabTexture
        GrabPass
        {
            "_GrabTexture"
        }

        CGPROGRAM
        #pragma surface surf Standard vertex:vert fullforwardshadows
        #pragma target 4.0
        

        sampler2D _DisplacementTex;
        float4 _DisplacementTex_ST;

        struct Input
        {
            float2 uv_NormalTex;
            float2 uv_DistortionTex;
            float2 uv_FoamTex;
            float2 uv_FoamDistortionTex;
            float4 grabPassUV;
            float4 screenPos;
            float3 worldPos;
        };

        sampler2D _FoamTex;
        sampler2D _FoamDistortionTex;
        float _FoamDistortionAmount;
        sampler2D _NormalTex;
        sampler2D _DistortionTex;
        
        float4 _WaterSurfaceColor;
        float4 _WaterShoreColor;
        float4 _WaterDeepColor;
        float _WorldReflectionStrength;

        float _NearShoreThreshold;
        float _DeepThreshold;

        float _NormalStrength;
        float2 _NormalSpeed;
        float _DistortionAmount;
        float2 _DistortionSpeed;
        float _DisplacementAmount;
        float2 _DisplacementSpeed;

        float _FoamCutoff;
        float2 _FoamSpeed;
        float _FoamDistance;

        float _MainAlpha;
        half _Glossiness;
        half _Metallic;

        sampler2D _CameraDepthTexture;
        sampler2D _GrabTexture;
        //Global reflection texture coming from "SurfaceReflection" script
        uniform sampler2D _WorldReflectionTex;
        

        UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

        void vert(inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input,o);
            float4 clipSpacePos = UnityObjectToClipPos(v.vertex);
            o.grabPassUV = ComputeScreenPos(clipSpacePos);

            float4 displacementTex = tex2Dlod(_DisplacementTex, float4(v.texcoord.xy * _DisplacementTex_ST + _Time.y * _DisplacementSpeed, 0, 0));
            v.vertex.y += displacementTex.y * _DisplacementAmount;
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            //Depth based water color
            float depthNonLinear = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(IN.screenPos));
            float depthLinear = LinearEyeDepth(depthNonLinear);
            float depthFromSurface = depthLinear - IN.screenPos.w;
            float deepDistBasedDepth = saturate(depthFromSurface / _DeepThreshold);
            float shoreDistBasedDepth = saturate(depthFromSurface / _NearShoreThreshold);
            float4 waterColor = lerp(lerp(_WaterShoreColor, _WaterSurfaceColor, shoreDistBasedDepth), _WaterDeepColor, deepDistBasedDepth);

            //Normal Map to make water surface curlier
            float3 normalTex = UnpackNormalWithScale(tex2D(_NormalTex, IN.uv_NormalTex + _Time.y * _NormalSpeed), _NormalStrength); 
            
            //Grab-pass fake refraction
            float3 distortionTex = UnpackNormal(tex2D(_DistortionTex, IN.uv_DistortionTex + _Time.y * _DistortionSpeed));
            distortionTex.xy *= _DistortionAmount;
            IN.grabPassUV.xy += distortionTex.xy * IN.grabPassUV.z;
            float4 grabTex = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(IN.grabPassUV));

            //Planar reflection
            float4 worldReflTex = tex2Dproj(_WorldReflectionTex, UNITY_PROJ_COORD(IN.grabPassUV));
            
            //Foam
            float foamDistBasedDepth = saturate(depthFromSurface / _FoamDistance);
            float foamCutOff = foamDistBasedDepth * _FoamCutoff;
            float2 foamDistTex = (tex2D(_FoamDistortionTex, IN.uv_FoamDistortionTex).xy * 2 - 1) * _FoamDistortionAmount;
            float2 foamUV = float2((IN.uv_FoamTex.x + _Time.y * _FoamSpeed.x) + foamDistTex.x, (IN.uv_FoamTex.y + _Time.y * _FoamSpeed.y) + foamDistTex.y);
            float foamTex = tex2D(_FoamTex, foamUV).r;
            float foam = foamTex > foamCutOff ? 1 : 0;
            float4 c = waterColor * grabTex;
            
            //Render
            o.Albedo = c.rgb + foam;

            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = _MainAlpha;
            o.Emission = worldReflTex * _WorldReflectionStrength;
            o.Normal = normalTex;

        }
        ENDCG
    }
    FallBack "Diffuse"
}