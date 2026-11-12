VARYING vec4 vColor;
VARYING float vDepth;
void MAIN()
{
    // 1 up to fadeNear, down to floorLevel at fadeFar; nearBoost brightens the closest lines
    float f = mix(floorLevel, 1.0, 1.0 - smoothstep(fadeNear, fadeFar, vDepth));
    float boost = mix(nearBoost, 1.0, smoothstep(0.0, fadeNear * 2.0, vDepth));
    FRAGCOLOR = vec4(vColor.rgb * f * boost, 1.0);
}
