cbuffer ModelViewProjectionConstantBuffer : register(b0)
{
	matrix model;
	matrix view;
	matrix projection;
};

struct VS_Canvas
{
	float4 Position   : SV_POSITION;
	float2 canvasXY  : TEXCOORD0;
};


VS_Canvas main(float4 vPos : POSITION)
{
	VS_Canvas Output;

	Output.Position = float4(sign(vPos.xy), 0, 1);

	float AspectRatio = projection._m11 / projection._m00;
	Output.canvasXY = sign(vPos.xy) * float2(AspectRatio, 1.0);

	return Output;
}