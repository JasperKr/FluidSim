

#ifdef PIXEL

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(tex, texture_coords);
    if (pixel.a < 0.4) {
        discard;
    }
    return pixel * color;
}

#endif