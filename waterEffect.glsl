#ifdef PIXEL

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {

    vec3 average = vec3(0.0);

    vec2 texelSize = 1.0 / love_ScreenSize.xy;
    float radius = 5.0;
    float samples = 0.0;

    for (int x = -3; x <= 3; x++) {
        for (int y = -3; y <= 3; y++) {

            vec2 offset = vec2(x, y) * texelSize * radius;

            vec3 pixel = Texel(tex, texture_coords + offset).rgb;
            pixel.r = max(min(pixel.r - 0.3, pixel.r / 2), pixel.r / 3) / 1.5;
            pixel.g = max(min(pixel.g - 0.3, pixel.g / 2), pixel.g / 3) / 1.5;
            pixel.b = max(min(pixel.b - 0.3, pixel.b / 2), pixel.b / 3) / 1.5;
            average += pixel;
            samples++;
        }
    }

    average /= samples;

    return vec4(average, 0.7) * color;
}

#endif