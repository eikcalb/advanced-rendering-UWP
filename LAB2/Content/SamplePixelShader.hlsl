#define vec2 float2
#define vec3 float3 
#define vec4 float4 
#define mat2 float2x2 
#define mat3 float3x3 

struct VS_Canvas
{
	float4 Position   : SV_POSITION;
	float2 canvasXY   : TEXCOORD0;
};

static float4 Eye = float4(0, 0, 10, 1);//eye position 
static float nearPlane = 1.0;
static float farPlane = 1000.0;

static float4 LightColor = float4(1, 1, 1, 1);
static float3 LightPos = float3(0, 100, 0);
static float4 backgroundColor = float4(0.1, 0.2, 0.3, 1);

static const int MAX_MARCHING_STEPS = 255;
static const float MIN_DIST = 0.0;
static const float MAX_DIST = 100.0;
static const float EPSILON = 0.0001;

struct Ray {
	float3 o;   // origin 
	float3 d;   // direction 
};

vec3 rayDirection(float fieldOfView, vec2 size, vec2 fragCoord) {
	vec2 xy = fragCoord - size / 2.0;
	float z = size.y / tan(radians(fieldOfView) / 2.0);
	return normalize(vec3(xy, -z));
}

float sphereSDF(vec3 samplePoint) {
	return length(samplePoint) - 1.0;
}

float sceneSDF(vec3 samplePoint) {
	return sphereSDF(samplePoint);
}

float shortestDistanceToSurface(vec3 eye, vec3 marchingDirection, float start, float end) {
	float depth = start;
	for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
		float dist = sceneSDF(eye + depth * marchingDirection);
		if (dist < EPSILON) {
			return depth;
		}
		depth += dist;
		if (depth >= end) {
			return end;
		}
	}
	return end;
}

vec3 estimateNormal(vec3 p) {
	return normalize(vec3(
		sceneSDF(vec3(p.x + EPSILON, p.y, p.z)) - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)),
		sceneSDF(vec3(p.x, p.y + EPSILON, p.z)) - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)),
		sceneSDF(vec3(p.x, p.y, p.z + EPSILON)) - sceneSDF(vec3(p.x, p.y, p.z - EPSILON))
	));
}

vec3 phongContribForLight(vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye,
	vec3 lightPos, vec3 lightIntensity) {
	vec3 N = estimateNormal(p);
	vec3 L = normalize(lightPos - p);
	vec3 V = normalize(eye - p);
	vec3 R = normalize(reflect(-L, N));

	float dotLN = dot(L, N);
	float dotRV = dot(R, V);

	if (dotLN < 0.0) {
		// Light not visible from this point on the surface
		return vec3(0.0, 0.0, 0.0);
	}

	if (dotRV < 0.0) {
		// Light reflection in opposite direction as viewer, apply only diffuse
		// component
		return lightIntensity * (k_d * dotLN);
	}
	return lightIntensity * (k_d * dotLN + k_s * pow(dotRV, alpha));
}

vec3 phongIllumination(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye) {
	const vec3 ambientLight = 0.5 * vec3(1.0, 1.0, 1.0);
	vec3 color = ambientLight * k_a;

	vec3 light1Pos = vec3(4.0 * sin(iTime),
		2.0,
		4.0 * cos(iTime));
	vec3 light1Intensity = vec3(0.4, 0.4, 0.4);

	color += phongContribForLight(k_d, k_s, alpha, p, eye,
		light1Pos,
		light1Intensity);

	vec3 light2Pos = vec3(2.0 * sin(0.37 * iTime),
		2.0 * cos(0.37 * iTime),
		2.0);
	vec3 light2Intensity = vec3(0.4, 0.4, 0.4);

	color += phongContribForLight(k_d, k_s, alpha, p, eye,
		light2Pos,
		light2Intensity);
	return color;
}

void mainImage(Ray ray, out vec4 fragColor, in vec2 fragCoord)
{
	float dist = shortestDistanceToSurface(ray.o, ray.d, MIN_DIST, MAX_DIST);

	if (dist > MAX_DIST - EPSILON) {
		// Didn't hit anything
		fragColor = vec4(0.0, 0.0, 0.0, 0.0);
		return;
	}
	vec3 p = Eye.xyz + dist * dir;

	vec3 K_a = vec3(0.2, 0.2, 0.2);
	vec3 K_d = vec3(0.7, 0.2, 0.2);
	vec3 K_s = vec3(1.0, 1.0, 1.0);
	float shininess = 10.0;

	vec3 color = phongIllumination(K_a, K_d, K_s, shininess, p, eye);

	fragColor = vec4(1.0, 0.0, 0.0, 1.0);
}

float4 main(VS_Canvas input) : SV_Target
{
	// specify primary ray: 
   Ray eyeray;
   eyeray.o = Eye.xyz;

   // set ray direction in view space 
	float dist2Imageplane = 5.0;
	float3 viewDir = float3(input.canvasXY, -dist2Imageplane);
	eyeray.d = normalize(viewDir);

	float4 fragColor;
	mainImage(eyeray, fragColor, input.Position.xy);

	return fragColor;
}