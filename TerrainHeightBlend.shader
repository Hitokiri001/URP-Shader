Shader "Universal Render Pipeline/Custom/ProceduralTerrain"
{
    Properties
    {
        [Header(Layer 1 Lowest)]
        [Space(10)]
        _BaseMap1("Texture 1", 2D) = "white" {}
        _BaseColor1("Color 1", Color) = (0.8, 0.7, 0.5, 1)
        _StartHeight1("Start Height 1", Range(0, 1)) = 0.0
        
        [Header(Layer 2)]
        [Space(10)]
        _BaseMap2("Texture 2", 2D) = "white" {}
        _BaseColor2("Color 2", Color) = (0.3, 0.6, 0.3, 1)
        _StartHeight2("Start Height 2", Range(0, 1)) = 0.25
        
        [Header(Layer 3)]
        [Space(10)]
        _BaseMap3("Texture 3", 2D) = "white" {}
        _BaseColor3("Color 3", Color) = (0.5, 0.5, 0.5, 1)
        _StartHeight3("Start Height 3", Range(0, 1)) = 0.5
        
        [Header(Layer 4 Highest)]
        [Space(10)]
        _BaseMap4("Texture 4", 2D) = "white" {}
        _BaseColor4("Color 4", Color) = (1, 1, 1, 1)
        _StartHeight4("Start Height 4", Range(0, 1)) = 0.75
        
        [Header(Blending)]
        [Space(10)]
        [Toggle] _UseBlending("Enable Layer Blending", Float) = 0
        _BlendRange("Blend Range", Range(0.01, 0.5)) = 0.1
        
        [Header(Height Range)]
        [Space(10)]
        _MinHeight("World Min Height", Float) = 0.0
        _MaxHeight("World Max Height", Float) = 100.0
        
        [Header(Settings)]
        [Space(10)]
        _Tiling("Texture Tiling", Float) = 0.1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _USEBLENDING_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap1); SAMPLER(sampler_BaseMap1);
            TEXTURE2D(_BaseMap2); SAMPLER(sampler_BaseMap2);
            TEXTURE2D(_BaseMap3); SAMPLER(sampler_BaseMap3);
            TEXTURE2D(_BaseMap4); SAMPLER(sampler_BaseMap4);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor1;
                float4 _BaseColor2;
                float4 _BaseColor3;
                float4 _BaseColor4;
                float4 _BaseMap1_ST;
                float _MinHeight;
                float _MaxHeight;
                float _StartHeight1;
                float _StartHeight2;
                float _StartHeight3;
                float _StartHeight4;
                float _UseBlending;
                float _BlendRange;
                float _Tiling;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionHCS = TransformWorldToHClip(OUT.positionWS);
                OUT.uv = IN.uv;
                
                VertexNormalInputs normalInput = GetVertexNormalInputs(IN.normalOS);
                OUT.normalWS = normalInput.normalWS;
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // Use world-space XZ coordinates for tiling
                float2 tiledUV = IN.positionWS.xz * _Tiling;

                // Sample all layer textures
                half4 tex1 = SAMPLE_TEXTURE2D(_BaseMap1, sampler_BaseMap1, tiledUV) * _BaseColor1;
                half4 tex2 = SAMPLE_TEXTURE2D(_BaseMap2, sampler_BaseMap2, tiledUV) * _BaseColor2;
                half4 tex3 = SAMPLE_TEXTURE2D(_BaseMap3, sampler_BaseMap3, tiledUV) * _BaseColor3;
                half4 tex4 = SAMPLE_TEXTURE2D(_BaseMap4, sampler_BaseMap4, tiledUV) * _BaseColor4;

                // Normalize mesh height to 0-1 based on world-space range
                float normalizedHeight = saturate((IN.positionWS.y - _MinHeight) / max(_MaxHeight - _MinHeight, 0.001));

                half4 finalColor;

                #ifdef _USEBLENDING_ON
                    // BLENDING MODE: Smooth transitions between layers
                    
                    // Calculate blend weights for each transition
                    float blend12 = saturate((normalizedHeight - _StartHeight2) / _BlendRange);
                    float blend23 = saturate((normalizedHeight - _StartHeight3) / _BlendRange);
                    float blend34 = saturate((normalizedHeight - _StartHeight4) / _BlendRange);

                    // Blend layers progressively
                    half4 result12 = lerp(tex1, tex2, blend12);
                    half4 result23 = lerp(result12, tex3, blend23);
                    finalColor = lerp(result23, tex4, blend34);
                    
                #else
                    // HARD MODE: No blending, instant layer switches
                    
                    if (normalizedHeight >= _StartHeight4)
                    {
                        finalColor = tex4;
                    }
                    else if (normalizedHeight >= _StartHeight3)
                    {
                        finalColor = tex3;
                    }
                    else if (normalizedHeight >= _StartHeight2)
                    {
                        finalColor = tex2;
                    }
                    else
                    {
                        finalColor = tex1;
                    }
                    
                #endif

                // Simple lighting (ambient + main light)
                Light mainLight = GetMainLight();
                half3 lighting = mainLight.color * mainLight.distanceAttenuation;
                half3 ambient = half3(0.3, 0.3, 0.3);
                
                half NdotL = saturate(dot(IN.normalWS, mainLight.direction));
                half3 diffuse = lighting * NdotL;
                
                finalColor.rgb *= (ambient + diffuse);

                return finalColor;
            }
            ENDHLSL
        }
        
        // Shadow caster pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}