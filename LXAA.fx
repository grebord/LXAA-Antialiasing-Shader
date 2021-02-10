/*--------------------------------------------------------------------------*/
namespace 					 	  LXAA										 {
/*		     Fast antialiasing shader by G.Rebord, for Reshade	
			 Based on FXAA3 CONSOLE version by TIMOTHY LOTTES
------------------------------------------------------------------------------
THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
============================================================================*/
#ifndef LXAA_EDGE_THRES
	// Edge detection threshold. With lower values more edges are detected.
	// The form of edge detection used here is much better than a simple luma
	// delta, improving both fidelity and performance.
	// Range: [0;1]. Default: 0.375 (thorough)
	#define LXAA_EDGE_THRES 0.375
#endif
#ifndef LXAA_LINE_CHECK
	// Enable to make near-horizontal/near-vertical lines smoother, which
	// requires additional checks. This brings a substantial jump in quality.
	#define LXAA_LINE_CHECK 1
#endif
/*==========================================================================*/
texture BackBufferTex : COLOR;
sampler BackBuffer {
	Texture = BackBufferTex;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	SRGBTexture = false;
};
static const float2 RCP2 = float2(BUFFER_RCP_WIDTH * 2,BUFFER_RCP_HEIGHT * 2);
/*--------------------------------------------------------------------------*/
#define tsp(p) 				float4(p, 0.0, 0.0)
#define GetLuma(c)			dot(c, float3(0.299, 0.587, 0.114))
#define SampleColor(p) 		tex2Dlod(BackBuffer, tsp(p)).rgb
#define SampleLumaOff(p, o) GetLuma(tex2Dlodoffset(BackBuffer, tsp(p), o).rgb)
/*--------------------------------------------------------------------------*/
#define OffSW 				int2(-1, 1)
#define OffSE 				int2( 1, 1)
#define OffNE 				int2( 1,-1)
#define OffNW 				int2(-1,-1)
/*--------------------------------------------------------------------------*/
#define LXAA_OFF_MIN		0.0625
#define LXAA_PROP_MAIN		0.4
#define LXAA_PROP_EACH_NP	0.3

/*==========================================================================*/
void LXAAVS(in uint id : SV_VertexID,
	out float4 pos : SV_Position, out float2 tco : TEXCOORD) {
	tco.x = (id == 2) ? 2.0 : 0.0;
	tco.y = (id == 1) ? 2.0 : 0.0;
	pos = float4(tco * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}	
/*==========================================================================*/
float3 LXAAPS
(float4 pos : SV_Position, noperspective float2 tco : TEXCOORD) : SV_Target
{
/*--------------------------------------------------------------------------*/
	float4 lumaA;
	lumaA.x = SampleLumaOff(tco, OffSW);
	lumaA.y = SampleLumaOff(tco, OffSE);
	lumaA.z = SampleLumaOff(tco, OffNE);
	lumaA.w = SampleLumaOff(tco, OffNW);
/*--------------------------------------------------------------------------*/
    float gradientSWNE = lumaA.x - lumaA.z;
	float gradientSENW = lumaA.y - lumaA.w;
	float2 dir;
    dir.x = gradientSWNE + gradientSENW;
    dir.y = gradientSWNE - gradientSENW;
/*--------------------------------------------------------------------------*/
	float2 dirM = abs(dir);
	float lumaAMax = max(max(lumaA.x, lumaA.y), max(lumaA.z, lumaA.w));
	float localLumaFactor = lumaAMax * 0.5 + 0.5;
	float localThres = LXAA_EDGE_THRES * localLumaFactor;
	bool lowDelta = abs(dirM.x - dirM.y) < localThres;
	if(lowDelta) discard;
/*--------------------------------------------------------------------------*/
	float dirMMin = min(dirM.x, dirM.y);
	float2 offM = saturate(LXAA_OFF_MIN * dirM / dirMMin);
	float2 offMult = RCP2 * sign(dir);
/*--------------------------------------------------------------------------*/
#if LXAA_LINE_CHECK
	float offMMax = max(offM.x, offM.y);
	if(offMMax == 1.0) {
		bool horSpan = offM.x == 1.0;
		bool negSpan = horSpan ? offMult.x < 0 : offMult.y < 0;
		bool sowSpan = horSpan == negSpan;
		float2 tcoC = tco;
		if( horSpan) tcoC.x += 2.0 * offMult.x;
		if(!horSpan) tcoC.y += 2.0 * offMult.y;
/*--------------------------------------------------------------------------*/
		float4 lumaAC = lumaA;
		if( sowSpan) lumaAC.x = SampleLumaOff(tcoC, OffSW);
		if(!negSpan) lumaAC.y = SampleLumaOff(tcoC, OffSE);
		if(!sowSpan) lumaAC.z = SampleLumaOff(tcoC, OffNE);
		if( negSpan) lumaAC.w = SampleLumaOff(tcoC, OffNW);
/*--------------------------------------------------------------------------*/
		float gradientSWNEC = lumaAC.x - lumaAC.z;
		float gradientSENWC = lumaAC.y - lumaAC.w;
		float2 dirC;
		dirC.x = gradientSWNEC + gradientSENWC;
		dirC.y = gradientSWNEC - gradientSENWC;
/*--------------------------------------------------------------------------*/
		if(!horSpan) dirC = dirC.yx;
		bool passC = abs(dirC.x) > 2.0 * abs(dirC.y);
		if(passC) offMult *= 2.0;
	}
#endif
/*--------------------------------------------------------------------------*/
	float2 offset = offM * offMult;
/*--------------------------------------------------------------------------*/
	float3 rgbM = SampleColor(tco);
    float3 rgbN = SampleColor(tco - offset);
    float3 rgbP = SampleColor(tco + offset);
    float3 rgbR = (rgbN + rgbP) * LXAA_PROP_EACH_NP + rgbM * LXAA_PROP_MAIN;
/*--------------------------------------------------------------------------*/
	float lumaR = GetLuma(rgbR);
	float lumaAMin = min(min(lumaA.x, lumaA.y), min(lumaA.z, lumaA.w));
    bool outOfRange = (lumaR < lumaAMin) || (lumaR > lumaAMax);
    if(outOfRange) discard;
/*--------------------------------------------------------------------------*/
	return rgbR;
}
/*==========================================================================*/
technique LXAA {
	pass {
		VertexShader = LXAAVS;
		PixelShader  = LXAAPS;
	}
}
}