// Define the shader type as a sky environment for Godot
shader_type sky;

// Group uniform parameters for sky gradient colors in the inspector
group_uniforms sky_colors;
// Define the top color of the sky dome
uniform vec3 top_color : source_color = vec3(0.15, 0.4, 0.75);
// Define the bottom color of the sky near the horizon
uniform vec3 bottom_color : source_color = vec3(0.55, 0.7, 0.85);

// Group uniform parameters for cloud rendering and behavior
group_uniforms clouds;
// Define the base color and transparency of the clouds
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Define the horizontal movement speed of the clouds over time
uniform float cloud_speed : hint_range(0.0, 5.0) = 0.8;
// Define the overall coverage density of the clouds across the sky
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.7;
// Define the scaling/tiling size of the cloud pattern
uniform float cloud_scale : hint_range(0.1, 5.0) = 2.5;
// Define the lighting brightness multiplier for clouds
uniform float cloud_brightness : hint_range(0.5, 3.0) = 1.0;
// Define the edge sharpness of the cloud formations
uniform float cloud_sharpness : hint_range(0.05, 0.5) = 0.3;
// Define the intensity of the atmospheric glow near the horizon
uniform float horizon_glow : hint_range(0.0, 2.0) = 0.5;

// Group uniform parameters for star rendering and control options
group_uniforms stars;
// Checkbox toggle: When unticked, stars code is completely skipped to save performance
uniform bool enable_stars = false;
// Define the overall visibility intensity of the stars
uniform float stars_intensity : hint_range(0.0, 5.0, 0.1) = 1.0;
// Define the custom color tint for the stars
uniform vec4 star_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Define the twinkling animation speed for the stars
uniform float twinkle_speed : hint_range(0.1, 5.0, 0.1) = 2.0;

// Fast 2D hash function for lightweight pseudo-random number generation
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// 3D hash function used for procedural cellular calculations
vec3 hash3( vec3 x ){
    x = vec3( dot(x,vec3(127.1,311.7, 74.7)),
              dot(x,vec3(269.5,183.3,246.1)),
              dot(x,vec3(113.5,271.9,124.6)));
    return fract(sin(x)*43758.5453123);
}

// Voronoi cell method for generating realistic stars with varying sizes
vec3 voronoi( in vec3 x ){
    vec3 p = floor( x );
    vec3 f = fract( x );
    
    float id = 0.0;
    vec2 res = vec2( 100.0 );
    for( int k=-1; k<=1; k++ )
    for( int j=-1; j<=1; j++ )
    for( int i=-1; i<=1; i++ ) {
        vec3 b = vec3( float(i), float(j), float(k) );
        vec3 r = vec3( b ) - f + hash3( p + b );
        float d = dot( r, r );
        if( d < res.x ) {
            id = dot( p+b, vec3(1.0,57.0,113.0 ) );
            res = vec2( d, res.x );
        } else if( d < res.y ) {
            res.y = d;
        }
    }
    return vec3( sqrt( res ), abs(id) );
}

// Noise interpolation function for smooth procedural texturing
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion (FBM) function to combine noise octaves for clouds
float fbm(vec2 p) {
    float total = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        total += amp * noise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return total;
}

// Main Godot sky shader execution function called per pixel
void sky() {
    // Extract the vertical component of the eye view direction
    float ed = EYEDIR.y;
    
    // Calculate the vertical gradient factor from top to bottom
    float gradient_fac = clamp(ed * 1.3, 0.0, 1.0);
    // Mix bottom color and top color based on the computed gradient
    vec3 final_color = mix(bottom_color, top_color, gradient_fac);
    
    // Compute atmospheric glow effect near the horizon line
    float h_glow = exp(-abs(ed) * 6.0) * horizon_glow;
    // Add the horizon glow contribution to the final color buffer
    final_color += bottom_color * h_glow;
    
    // Initialize cloud shape factor variable to zero
    float cloud_shape = 0.0;
    // Evaluate cloud placement only if above or near the horizon
    if (ed > -0.05) {
        // Wrap TIME using mod() to prevent floating-point precision loss and stuttering issues
        vec2 time_offset = vec2(mod(TIME * cloud_speed * 0.6, 200.0), mod(TIME * cloud_speed * 0.2, 200.0));
        // Project dome UV coordinates and add the wrapped time offset for fluid movement
        vec2 uv = (EYEDIR.xz / (abs(ed) + 0.2)) * cloud_scale + time_offset;
        
        float n1 = fbm(uv);
        float n2 = fbm(uv * 1.8 + vec2(2.1, 3.4));
        float combined_clouds = n1 * 0.65 + n2 * 0.35;
        
        cloud_shape = smoothstep(1.0 - cloud_coverage, (1.0 - cloud_coverage) + cloud_sharpness, combined_clouds);
        
        // Apply smooth fade near horizon for natural visual blending
        float horizon_fade = smoothstep(-0.02, 0.15, ed);
        cloud_shape *= horizon_fade;
    }
    
    // Stars rendering block: Bypassed completely if checkbox is unticked (zero performance cost)
    if (enable_stars && stars_intensity > 0.0 && ed > 0.02 && cloud_shape < 0.05) {
        vec3 star_dir = EYEDIR;
        vec2 stars = voronoi(star_dir * 30.0).xz;
        
        float size_rand = hash3(vec3(stars.y)).x;
        float thickness = mix(0.015, 0.04, size_rand);
        
        float twinkle = smoothstep(thickness + ((1.0 + sin(TIME * twinkle_speed + stars.y * 10.0)) / 2.0) * 0.02, 0.0, stars.x);
        
        // Apply smooth mask falloff towards the horizon boundary
        float view_mask = smoothstep(0.02, 0.2, ed);
        final_color += star_color.rgb * (twinkle * stars_intensity * view_mask * (0.5 + size_rand * 0.5));
    }
    
    // Render clouds layer on top of the sky and stars background
    if (ed > -0.05 && cloud_shape > 0.0) {
        vec3 final_cloud_col = cloud_color.rgb * cloud_brightness;
        final_color = mix(final_color, final_cloud_col, cloud_shape * 0.9);
    }
    
    // Assign the final computed pixel color to the output variable
    COLOR = final_color;
}