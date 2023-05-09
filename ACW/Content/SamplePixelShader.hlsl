Texture2D tex : register(t0);
SamplerState samplerM : register(s0);

cbuffer ConstantBuffer : register(b0)
{
    matrix projectionMatrix;
    matrix viewMatrix;
    matrix modelMatrix;
};

struct PS_INPUT
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    float3 normal : NORMAL;
};

float4 main(PS_INPUT input) : SV_TARGET
{
    float4 texColor = tex.Sample(samplerM, input.texcoord);

    // Compute water color based on depth
    float depth = input.position.z / input.position.w;
    float3 waterColor = lerp(float3(0.0f, 0.5f, 1.0f), float3(0.0f, 0.2f, 0.6f), depth);
    // Compute distortion based on normal vector
    float3 distortion = input.normal * 0.05f;
    float2 distortedCoord = input.texcoord + distortion.xy;

    // Sample texture with distorted coordinates
    float4 distortedColor = tex.Sample(samplerM, distortedCoord);

    // Blend distorted color with water color based on depth
    float4 finalColor = lerp(texColor, distortedColor, depth);
    finalColor.xyz = lerp(finalColor.xyz, waterColor, 0.5f);

    return finalColor;
}
