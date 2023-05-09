texture2D baseTexture : register(t0);
SamplerState samplerM : register(s0);

cbuffer ModelViewProjectionConstantBuffer : register(b0)
{
	matrix model;
	matrix view;
	matrix projection;
	float2 variant;
};

#define vec2 float2
#define vec3 float3
#define vec4 float4
#define mat2 float2x2
#define mat3 float3x3
#define mix lerp
#define fract frac

#define TAU 6.28318530718
#define MAX_ITER 5

#define iTime variant.x
#define mod(x,y) (x-y*floor(x/y))

Buffer<float4> g_ParticleBuffer;
Buffer<float4> g_ParticleBuffer1;

float speck(vec2 pos, vec2 uv, float radius)
{
	pos.y += 0.05;
	float color = distance(pos, uv);
	vec3 tex = baseTexture.Sample(samplerM, sin(vec2(uv) * 10.1)).xyz;
	vec3 tex2 = baseTexture.Sample(samplerM, sin(vec2(pos) * 10.1)).xyz;
	color = clamp((1.0 - pow(color * (5.0 / radius), pow(radius, 0.9))), 0.0, 1.0);
	color *= clamp(mix(sin(tex.y) + 0.1, cos(tex.x), 0.5) * sin(tex2.x) + 0.2, 0.0, 1.0);
	return color;
}

vec3 caustic(vec2 uv)
{
	vec2 p = mod(uv * TAU, TAU) - 250.0;
	float time = iTime * .5 + 23.0;

	vec2 i = vec2(p);
	float c = 1.0;
	float inten = .005;

	for (int n = 0; n < MAX_ITER; n++)
	{
		float t = time * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
	}

	c /= float(MAX_ITER);
	c = 1.17 - pow(c, 1.4);
	vec3 color = vec3(pow(abs(c), 8.0), pow(abs(c), 8.0), pow(abs(c), 8.0));
	color = clamp(color + vec3(0.0, 0.35, 0.5), 0.0, 1.0);
	color = mix(color, vec3(1.0, 1.0, 1.0), 0.3);

	return color;
}


// perf increase for god ray, eliminates Y
float causticX(float x, float power, float gtime)
{
	float p = mod(x * TAU, TAU) - 250.0;
	float time = gtime * .5 + 23.0;

	float i = p;;
	float c = 1.0;
	float inten = .005;

	for (int n = 0; n < MAX_ITER / 2; n++)
	{
		float t = time * (1.0 - (3.5 / float(n + 1)));
		i = p + cos(t - i) + sin(t + i);
		c += 1.0 / length(p / (sin(i + t) / inten));
	}
	c /= float(MAX_ITER);
	c = 1.17 - pow(c, power);

	return c;
}


float GodRays(vec2 uv)
{
	float light = 0.0;

	light += pow(causticX((uv.x + 0.08 * uv.y) / 1.7 + 0.5, 1.8, iTime * 0.65), 10.0) * 0.05;
	light -= pow((1.0 - uv.y) * 0.3, 2.0) * 0.2;
	light += pow(causticX(sin(uv.x), 0.3, iTime * 0.7), 9.0) * 0.4;
	light += pow(causticX(cos(uv.x * 2.3), 0.3, iTime * 1.3), 4.0) * 0.1;

	light -= pow((1.0 - uv.y) * 0.3, 3.0);
	light = clamp(light, 0.0, 1.0);

	return light;
}


float noise(in vec2 p)
{

	float height = mix(baseTexture.Sample(samplerM, p / 80.0).x, 1.0, 0.85);
	float height2 = mix(baseTexture.Sample(samplerM, p / 700.0).x, 0.0, -3.5);

	return height2 - height - 0.179;
}


float fBm(in vec2 p)
{
	float sum = 0.0;
	float amp = 1.0;

	for (int i = 0; i < 4; i++)
	{
		sum += amp * noise(p);
		amp *= 0.5;
		p *= 2.5;
	}
	return sum * 0.5 + 0.15;
}


vec3 raymarchTerrain(in vec3 ro, in vec3 rd, in float tmin, in float tmax)
{
	float t = tmin;
	vec3 res = vec3(-1.0, -1.0, -1.0);

	for (int i = 0; i < 110; i++)
	{
		vec3 p = ro + rd * t;

		res = vec3(vec2(0.0, p.y - fBm(p.xz)), t);

		float d = res.y;

		if (d < (0.001 * t) || t > tmax)
		{
			break;
		}

		t += 0.5 * d;
	}

	return res;
}


vec3 getTerrainNormal(in vec3 p)
{
	float eps = 0.025;
	return normalize(vec3(fBm(vec2(p.x - eps, p.z)) - fBm(vec2(p.x + eps, p.z)),
		2.0 * eps,
		fBm(vec2(p.x, p.z - eps)) - fBm(vec2(p.x, p.z + eps))));
}

struct PixelShaderInput
{
	float4 pos : SV_POSITION;
	float2 canvas : TEXCOORD0;
};


float4 main(PixelShaderInput input) : SV_Target
{
	vec3 skyColor = vec3(0.3, 1.0, 1.0);

	vec3 sunLightColor = vec3(1.7, 0.65, 0.65);
	vec3 skyLightColor = vec3(0.8, 0.35, 0.15);
	vec3 indLightColor = vec3(0.4, 0.3, 0.2);
	vec3 horizonColor = vec3(0.0, 0.05, 0.2);
	vec3 sunDirection = normalize(vec3(0.8, 0.8, 0.6));

	vec2 p = 2.0 * input.pos.xy;

	vec3 eye = vec3(0.0, 1.25, 1.5);
	vec2 rot = 6.2831 * (vec2(-0.05 + iTime * 0.01, 0.0 - sin(iTime * 0.5) * 0.01) + vec2(1.0, 0.0) / 1);
	eye.yz = cos(rot.y) * eye.yz + sin(rot.y) * eye.zy * vec2(-1.0, 1.0);
	eye.xz = cos(rot.x) * eye.xz + sin(rot.x) * eye.zx * vec2(1.0, -1.0);

	vec3 ro = eye;
	vec3 ta = vec3(0.5, 1.0, 0.0);

	vec3 cw = normalize(ta - ro);
	vec3 cu = normalize(cross(vec3(0.0, 1.0, 0.0), cw));
	vec3 cv = normalize(cross(cw, cu));
	mat3 cam = mat3(cu, cv, cw);

	vec3 rd = normalize(vec3(p.xy, 1.0));
	//vec3 rd = cam * normalize(vec3(p.xy, 1.0));

	// background
	vec3 color = skyColor;
	float sky = 0.0;

	// terrain marching
	float tmin = 0.1;
	float tmax = 20.0;
	vec3 res = raymarchTerrain(ro, rd, tmin, tmax);

	vec3 colorBubble = vec3(0.0, 0.0, 0.0);
	float bubble = 0.0;
	bubble += speck(vec2(sin(iTime * 0.32), cos(iTime) * 0.2 + 0.1), rd.xy, -0.08 * rd.z);
	bubble += speck(vec2(sin(1.0 - iTime * 0.39) + 0.5, cos(1.0 - iTime * 0.69) * 0.2 + 0.15), rd.xy, 0.07 * rd.z);
	bubble += speck(vec2(cos(1.0 - iTime * 0.5) - 0.5, sin(1.0 - iTime * 0.36) * 0.2 + 0.1), rd.xy, 0.12 * rd.z);
	bubble += speck(vec2(sin(iTime * 0.44) - 1.0, cos(1.0 - iTime * 0.32) * 0.2 + 0.15), rd.xy, -0.09 * rd.z);
	bubble += speck(vec2(1.0 - sin(1.0 - iTime * 0.6) - 1.3, sin(1.0 - iTime * 0.82) * 0.2 + 0.1), rd.xy, 0.15 * rd.z);

	colorBubble = bubble * vec3(0.2, 0.7, 1.0);
	if (rd.z < 0.1)
	{
		float y = 0.00;
		for (float x = 0.39; x < 6.28; x += 0.39)
		{
			vec3 height = baseTexture.Sample(samplerM, vec2(x, x)).xyz;
			y += 0.03 * height.x;
			bubble = speck(vec2(sin(iTime + x) * 0.5 + 0.2, cos(iTime * height.z * 2.1 + height.x * 1.7) * 0.2 + 0.2),
				rd.xy, (cos(iTime + height.y * 2.3 + rd.z * -1.0) * -0.01 + 0.25));
			colorBubble += bubble * vec3(-0.1 * rd.z, -0.5 * rd.z, 1.0);
		}
	}

	float t = res.z;

	if (t < tmax)
	{
		vec3 pos = ro + rd * t;
		vec3 nor;

		// add bumps
		nor = getTerrainNormal(pos);
		nor = normalize(nor + 0.5 * getTerrainNormal(pos * 8.0));

		float sun = clamp(dot(sunDirection, nor), 0.0, 1.0);
		sky = clamp(0.5 + 0.5 * nor.y, 0.0, 1.0);
		vec3 diffuse = mix(baseTexture.Sample(samplerM, vec2(pos.x * pow(pos.y, 0.01), pos.z * pow(pos.y, 0.01))).xyz, vec3(1.0, 1.0, 1.0), clamp(1.1 - pos.y, 0.0, 1.0));

		diffuse *= caustic(vec2(mix(pos.x, pos.y, 0.2), mix(pos.z, pos.y, 0.2)) * 1.1);
		vec3 lightColor = 1.0 * sun * sunLightColor;

		lightColor += 0.7 * sky * skyLightColor;

		color *= 0.8 * diffuse * lightColor;

		// fog
		color = mix(color, horizonColor, 1.0 - exp(-0.3 * pow(t, 1.0)));
	}
	else
	{
		sky = clamp(0.8 * (1.0 - 0.8 * rd.y), 0.0, 1.0);
		color = sky * skyColor;
		color += ((0.3 * caustic(vec2(p.x, p.y * 1.0))) + (0.3 * caustic(vec2(p.x, p.y * 2.7)))) * pow(p.y, 4.0);

		// horizon
		color = mix(color, horizonColor, pow(1.0 - pow(rd.y, 4.0), 20.0));
	}

	// special effects
	color += colorBubble;
	color += GodRays(p) * mix(skyColor, 1.0, p.y * p.y) * vec3(0.7, 1.0, 1.0);

	// gamma correction
	vec3 gamma = vec3(0.46, 0.46, 0.46);
	return vec4(pow(color, gamma), 1.0);
}
//
//float noise(float2 p)
//{
//	float height = lerp(g_ParticleBuffer.Load(int3(p / 80.0, -100)).x, 1.0, 0.85);
//	float height2 = lerp(g_ParticleBuffer1.Load(int3(p / 700.0, -200)).x, 0.0, -3.5);
//
//	return height2 - height - 0.179;
//}
//
//float speck(float2 pos, float2 uv, float radius)
//{
//	pos.y += 0.05;
//	float color = distance(pos, uv);
//	float3 tex = g_ParticleBuffer.Load(int3(sin(uv * 10.1), 0)).xyz;
//	float3 tex2 = g_ParticleBuffer.Load(int3(sin(pos * 10.1), 0)).xyz;
//	color = clamp((1.0 - pow(color * (5.0 / radius), pow(radius, 0.9))), 0.0, 1.0);
//	color *= clamp(lerp(sin(tex.y) + 0.1, cos(tex.x), 0.5) * sin(tex2.x) + 0.2, 0.0, 1.0);
//	return color;
//}
//
//float3 caustic(float2 uv)
//{
//	float2 p = fmod(uv * TAU, TAU) - 250.0;
//	float time = noise(2) * .5 + 23.0;
//	float2 i = p;
//	float c = 1.0;
//	float inten = .005;
//
//	for (int n = 0; n < MAX_ITER; n++)
//	{
//		float t = time * (1.0 - (3.5 / float(n + 1)));
//		i = p + float2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
//		c += 1.0 / length(float2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
//	}
//
//	c /= float(MAX_ITER);
//	c = 1.17 - pow(c, 1.4);
//	float3 color = pow(abs(c), 8.0);
//	color = clamp(color + float3(0.0, 0.35, 0.5), 0.0, 1.0);
//	color = lerp(color, float3(1.0, 1.0, 1.0), 0.3);
//
//	return color;
//}
//
//// perf increase for god ray, eliminates Y
//float causticX(float x, float power, float gtime)
//{
//	float p = fmod(x * TAU, TAU) - 250.0;
//	float time = gtime * .5 + 23.0;
//	float i = p;;
//	float c = 1.0;
//	float inten = .005;
//
//	for (int n = 0; n < MAX_ITER / 2; n++)
//	{
//		float t = time * (1.0 - (3.5 / float(n + 1)));
//		i = p + cos(t - i) + sin(t + i);
//		c += 1.0 / length(p / (sin(i + t) / inten));
//	}
//
//	c /= float(MAX_ITER);
//	c = 1.17 - pow(c, power);
//
//	return c;
//}
//
//float GodRays(float2 uv)
//{
//	float light = 0.0;
//	light += pow(causticX((uv.x + 0.08 * uv.y) / 1.7 + 0.5, 1.8, noise(1) * 0.65), 10.0) * 0.05;
//	light -= pow((1.0 - uv.y) * 0.3, 2.0) * 0.2;
//	light += pow(causticX(sin(uv.x), 0.3, noise(1) * 0.7), 9.0) * 0.4;
//	light += pow(causticX(cos(uv.x * 2.3), 0.3, noise(1) * 1.3), 4.0) * 0.1;
//
//	light -= pow((1.0 - uv.y) * 0.3, 3.0);
//	light = clamp(light, 0.0, 1.0);
//
//	return light;
//}
//
//float fBm(float2 p)
//{
//	float sum = 0.0;
//	float amp = 1.0;
//
//	for (int i = 0; i < 4; i++)
//	{
//		sum += amp * noise(p);
//		amp *= 0.5;
//		p *= 2.5;
//	}
//	return sum * 0.5 + 0.15;
//}
//
//float3 raymarchTerrain(float3 ro, float3 rd, float tmin, float tmax)
//{
//	float t = tmin;
//	float3 res = float3(-1.0, -1.0, -1.0);
//
//	for (int i = 0; i < 110; i++)
//	{
//		float3 p = ro + rd * t;
//
//		res = float3(float2(0.0, p.y - fBm(float2(p.xz))), t);
//
//		float d = res.y;
//
//		if (d < (0.001 * t) || t > tmax)
//		{
//			break;
//		}
//
//		t += 0.5 * d;
//	}
//
//	return res;
//}
//
//float3 getTerrainNormal(float3 p)
//{
//	float eps = 0.025;
//	return normalize(float3(fBm(float2(p.x - eps, p.z)) - fBm(float2(p.x + eps, p.z)),
//		2.0 * eps,
//		fBm(float2(p.x, p.z - eps)) - fBm(float2(p.x, p.z + eps))));
//}
//
//struct PixelShaderInput
//{
//	float4 pos : SV_POSITION;
//	float2 canvas : TEXCOORD0;
//};
//
//
//float4 main(PixelShaderInput input) : SV_Target // main(out float4 fragColor : SV_Target0, in float2 fragCoord : SV_Position)
//{
//	float3 skyColor = float3(0.3, 1.0, 1.0);
//	float3 sunLightColor = float3(1.7, 0.65, 0.65);
//	float3 skyLightColor = float3(0.8, 0.35, 0.15);
//	float3 indLightColor = float3(0.4, 0.3, 0.2);
//	float3 horizonColor = float3(0.0, 0.05, 0.2);
//	float3 sunDirection = normalize(float3(0.8, 0.8, 0.6));
//
//	float dist2Imageplane = 5.0;
//	float3 iResolution = float3(input.canvas, -dist2Imageplane);
//	iResolution = normalize(iResolution);
//	float2 p = (-iResolution.xy + 2.0 * input.pos.xy) / iResolution.y;
//
//	float3 eye = float3(10.0, -1.0, -100.5);
//	float2 rot = 6.2831 * (float2(-0.05 + noise(1) * 0.01, 0.0 - sin(noise(1) * 0.5) * 0.01) + float2(1.0, 0.0) * iResolution.xy * 0.25 / iResolution.x);
//	eye.yz = cos(rot.y) * eye.yz + sin(rot.y) * eye.zy * float2(-1.0, 1.0);
//	eye.xz = cos(rot.x) * eye.xz + sin(rot.x) * eye.zx * float2(1.0, -1.0);
//	float3 ro = eye;
//	float3 ta = float3(0.5, 1.0, 0.0);
//	float3 cw = normalize(ta - ro);
//	float3 cu = normalize(cross(float3(0.0, 1.0, 0.0), cw));
//	float3 cv = normalize(cross(cw, cu));
//	float3x3 cam = float3x3(cu, cv, cw);
//	float3 rd = normalize(float3(p.xy, 1.0));
//	// background
//	float3 color = skyColor;
//	float sky = 0.0;
//	// terrain marching
//	float tmin = 0.1;
//	float tmax = 20.0;
//	float3 res = raymarchTerrain(ro, rd, tmin, tmax);
//	float3 colorBubble = float3(0.0, 0.0, 0.0);
//	float bubble = 0.0;
//	bubble += speck(float2(sin(noise(1) * 0.32), cos(noise(1)) * 0.2 + 0.1), rd.xy, -0.08 * rd.z);
//	bubble += speck(float2(sin(1.0 - noise(1) * 0.39) + 0.5, cos(1.0 - noise(1) * 0.69) * 0.2 + 0.15), rd.xy, 0.07 * rd.z);
//	bubble += speck(float2(cos(1.0 - noise(1) * 0.5) - 0.5, sin(1.0 - noise(1) * 0.36) * 0.2 + 0.1), rd.xy, 0.12 * rd.z);
//	bubble += speck(float2(sin(noise(1) * 0.44) - 1.0, cos(1.0 - noise(1) * 0.32) * 0.2 + 0.15), rd.xy, -0.09 * rd.z);
//	bubble += speck(float2(1.0 - sin(1.0 - noise(1) * 0.6) - 1.3, sin(1.0 - noise(1) * 0.82) * 0.2 + 0.1), rd.xy, 0.15 * rd.z);
//
//	colorBubble = bubble * float3(0.2, 0.7, 1.0);
//	if (rd.z < 0.1)
//	{
//		float y = 0.00;
//		for (float x = 0.39; x < 6.28; x += 0.39)
//		{
//			float3 height = g_ParticleBuffer1.Load(int3(x, 0, 0)).xyz;
//			y += 0.03 * height.x;
//			bubble = speck(float2(sin(noise(1) + x) * 0.5 + 0.2, cos(noise(1) * height.z * 2.1 + height.x * 1.7) * 0.2 + 0.2),
//				rd.xy, (cos(noise(1) + height.y * 2.3 + rd.z * -1.0) * -0.01 + 0.25));
//			colorBubble += bubble * float3(-0.1 * rd.z, -0.5 * rd.z, 1.0);
//		}
//	}
//
//	float t = res.z;
//
//	if (t < tmax)
//	{
//		float3 pos = ro + rd * t;
//		float3 nor;
//
//		// add bumps
//		nor = getTerrainNormal(pos);
//		nor = normalize(nor + 0.5 * getTerrainNormal(pos * 8.0));
//
//		float sun = clamp(dot(sunDirection, nor), 0.0, 1.0);
//		sky = clamp(0.5 + 0.5 * nor.y, 0.0, 1.0);
//		float3 diffuse = lerp(g_ParticleBuffer1.Load(int3(pos.x * pow(pos.y, 0.01), pos.z * pow(pos.y, 0.01), 0)).xyz, float3(1.0, 1.0, 1.0), clamp(1.1 - pos.y, 0.0, 1.0));
//
//		diffuse *= caustic(float2(lerp(pos.x, pos.y, 0.2), lerp(pos.z, pos.y, 0.2)) * 1.1);
//		float3 lightColor = 1.0 * sun * sunLightColor;
//
//		lightColor += 0.7 * sky * skyLightColor;
//
//		color *= 0.8 * diffuse * lightColor;
//
//		// fog
//		color = lerp(color, horizonColor, 1.0 - exp(-0.3 * pow(t, 1.0)));
//	}
//	else
//	{
//		sky = clamp(0.8 * (1.0 - 0.8 * rd.y), 0.0, 1.0);
//		color = sky * skyColor;
//		color += ((0.3 * caustic(float2(p.x, p.y * 1.0))) + (0.3 * caustic(float2(p.x, p.y * 2.7)))) * pow(p.y, 4.0);
//
//		// horizon
//		color = lerp(color, horizonColor, pow(1.0 - pow(rd.y, 4.0), 20.0));
//	}
//
//	// special effects
//	color += colorBubble;
//	color += GodRays(p) * lerp(skyColor, 1.0, p.y * p.y) * float3(0.7, 1.0, 1.0);
//
//	// gamma correction
//	float3 gamma = 0.46;
//	
//	return float4(pow(color, gamma), 1.0);
//}