cbuffer ConstantBuffer : register(b0)
{
    matrix projectionMatrix;
    matrix viewMatrix;
    matrix modelMatrix;
};

struct VS_INPUT
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
};

struct VS_OUTPUT
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    float3 normal : NORMAL;
};

VS_OUTPUT main(VS_INPUT input)
{
    VS_OUTPUT output;

    // Transform vertex position and normal
    float4 position = float4(input.position, 1.0f);
    position = mul(position, modelMatrix);
    position = mul(position, viewMatrix);
    position = mul(position, projectionMatrix);
    output.position = position;

    float4 normal = float4(input.normal, 0.0f);
    normal = mul(normal, modelMatrix);
    normal = mul(normal, viewMatrix);
    normal = mul(normal, projectionMatrix);
    output.normal = normal.xyz;

    output.texcoord = input.texcoord;

    return output;
}
