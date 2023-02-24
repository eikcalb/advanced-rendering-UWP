struct VS_Canvas
{
	float4 Position   : SV_POSITION;
	float2 canvasXY   : TEXCOORD0;
};

float4 main(VS_Canvas In) : SV_Target
{
float4 RGBColor = float4(In.canvasXY  , 0.0, 1.0);
if (length(In.canvasXY) < 0.5)
RGBColor = float4(1, 0, 0, 1);
else
RGBColor = (float4)0.2;

return RGBColor;
}