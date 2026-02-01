struct Globals {
    surface_size: vec2f,
    viewport_origin: vec2f,
};

struct MsdfParams {
    fill_color: vec4f,
    outline_color: vec4f,
    px_range: f32,
    outline_width_px: f32,
    _padding: vec2f,
};

@group(0) @binding(0) var<uniform> globals: Globals;
@group(1) @binding(0) var ui_sampler: sampler;
@group(1) @binding(1) var ui_texture: texture_2d<f32>;
@group(2) @binding(0) var<uniform> msdf: MsdfParams;

struct VSIn {
    @location(0) position: vec2f,
    @location(1) uv: vec2f,
    @location(2) color: vec4f,
};

struct VSOut {
    @builtin(position) clip_position: vec4f,
    @location(0) uv: vec2f,
    @location(1) color: vec4f,
};

@vertex
fn vs_main(input: VSIn) -> VSOut {
    var out: VSOut;
    let pixel = input.position + globals.viewport_origin;
    let surface = globals.surface_size;
    let ndc = vec2<f32>(
        (pixel.x / surface.x) * 2.0 - 1.0,
        1.0 - (pixel.y / surface.y) * 2.0,
    );
    out.clip_position = vec4<f32>(ndc, 0.0, 1.0);
    out.uv = input.uv;
    out.color = input.color;
    return out;
}

fn sampleMsdf(texcoord: vec2f) -> f32 {
    let c = textureSample(ui_texture, ui_sampler, texcoord);
    return max(min(c.r, c.g), min(max(c.r, c.g), c.b));
}

fn premultiply(color: vec4f) -> vec4f {
    return vec4f(color.rgb * color.a, color.a);
}

@fragment
fn fs_main(input: VSOut) -> @location(0) vec4f {
    let texture_size = vec2f(textureDimensions(ui_texture, 0));
    let dx = texture_size.x * length(vec2f(dpdxFine(input.uv.x), dpdyFine(input.uv.x)));
    let dy = texture_size.y * length(vec2f(dpdxFine(input.uv.y), dpdyFine(input.uv.y)));
    let to_pixels = msdf.px_range * inverseSqrt(dx * dx + dy * dy);
    let sig_dist = sampleMsdf(input.uv) - 0.5;
    let px_dist = sig_dist * to_pixels;

    let edge_width = 0.5;
    let fill_alpha = smoothstep(-edge_width, edge_width, px_dist);
    let outline_alpha = smoothstep(-edge_width, edge_width, px_dist + msdf.outline_width_px);
    let outline_band = max(outline_alpha - fill_alpha, 0.0);

    let fill_color = vec4f(msdf.fill_color.rgb * input.color.rgb, msdf.fill_color.a * input.color.a);
    let outline_color = vec4f(msdf.outline_color.rgb, msdf.outline_color.a * input.color.a);

    let fill = premultiply(fill_color) * fill_alpha;
    let outline = premultiply(outline_color) * outline_band;
    let result = fill + outline;

    if (result.a < 0.001) {
        discard;
    }

    return result;
}
