VARYING vec4 vColor;
VARYING float vDepth;
void MAIN()
{
    vColor = COLOR;
    vec4 eye = VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0);
    vDepth = -eye.z;
    POINT_SIZE = pointSize;
    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(VERTEX, 1.0);
}
