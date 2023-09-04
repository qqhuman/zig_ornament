const std = @import("std");
const zmath = @import("zmath");

pub const Camera = struct {
    const Self = @This();
    origin: zmath.Vec,
    lower_left_corner: zmath.Vec,
    horizontal: zmath.Vec,
    vertical: zmath.Vec,
    u: zmath.Vec,
    v: zmath.Vec,
    w: zmath.Vec,
    lens_radius: f32,

    vfov: f32,
    focus_dist: f32,
    aspect_ratio: f32,
    lookfrom: zmath.Vec,
    lookat: zmath.Vec,
    vup: zmath.Vec,

    dirty: bool,

    pub fn init(
        lookfrom: zmath.Vec,
        lookat: zmath.Vec,
        vup: zmath.Vec,
        aspect_ratio: f32,
        vfov: f32,
        aperture: f32,
        focus_dist: f32,
    ) Self {
        const theta = std.math.degreesToRadians(f32, vfov);
        const h = std.math.tan(theta / 2.0);
        const viewport_height = 2.0 * h;
        const viewport_width = aspect_ratio * viewport_height;

        const w = zmath.normalize3(lookfrom - lookat);
        const u = zmath.normalize3(zmath.cross3(vup, w));
        const v = zmath.cross3(w, u);

        const origin = lookfrom;
        const horizontal = zmath.splat(zmath.Vec, focus_dist * viewport_width) * u;
        const vertical = zmath.splat(zmath.Vec, focus_dist * viewport_height) * v;
        const lower_left_corner =
            origin - horizontal / zmath.splat(zmath.Vec, 2.0) - vertical / zmath.splat(zmath.Vec, 2.0) - zmath.splat(zmath.Vec, focus_dist) * w;

        const lens_radius = aperture / 2.0;
        return .{
            .origin = origin,
            .lower_left_corner = lower_left_corner,
            .horizontal = horizontal,
            .vertical = vertical,
            .u = u,
            .v = v,
            .w = w,
            .lens_radius = lens_radius,

            .focus_dist = focus_dist,
            .vfov = vfov,
            .aspect_ratio = aspect_ratio,
            .lookfrom = lookfrom,
            .lookat = lookat,
            .vup = vup,

            .dirty = true,
        };
    }

    pub fn setAspectRatio(self: *Self, aspect_ratio: f32) void {
        self.* = Self.init(
            self.lookfrom,
            self.lookat,
            self.vup,
            aspect_ratio,
            self.vfov,
            2.0 * self.lens_radius,
            self.focus_dist,
        );
    }

    pub fn getAspectRatio(self: Self) f32 {
        return self.aspect_ratio;
    }

    pub fn getLookFrom(self: Self) zmath.Vec {
        return self.lookfrom;
    }

    pub fn getLookAt(self: Self) zmath.Vec {
        return self.lookat;
    }

    pub fn getVUp(self: Self) zmath.Vec {
        return self.vup;
    }

    pub fn setLookAt(
        self: *Self,
        lookfrom: zmath.Vec,
        lookat: zmath.Vec,
        vup: zmath.Vec,
    ) void {
        self.* = Camera.init(
            lookfrom,
            lookat,
            vup,
            self.aspect_ratio,
            self.vfov,
            2.0 * self.lens_radius,
            self.focus_dist,
        );
    }
};
