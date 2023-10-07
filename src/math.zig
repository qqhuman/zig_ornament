const std = @import("std");
const zmath = @import("zmath");

pub const unit_x = zmath.f32x4(1.0, 0.0, 0.0, 0.0);
pub const unit_y = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
pub const unit_z = zmath.f32x4(0.0, 0.0, 1.0, 0.0);

fn approx_eql(val1: f32, val2: f32) bool {
    const eps = 0.0000001;
    return std.math.fabs(val1 - val2) < eps;
}

pub fn rotationBetweenVectors(a: zmath.Vec, b: zmath.Vec) zmath.Mat {
    const k_cos_theta = zmath.dot3(a, b)[0];

    if (approx_eql(k_cos_theta, 1.0)) {
        return zmath.identity();
    }

    const k = zmath.sqrt(zmath.lengthSq3(a) * zmath.lengthSq3(b))[0];
    if (approx_eql(k_cos_theta / k, -1.0)) {
        var orthogonal = zmath.cross3(a, unit_x);
        if (approx_eql(zmath.lengthSq3(orthogonal)[0], 0.0)) {
            orthogonal = zmath.cross3(a, unit_y);
        }
        orthogonal = zmath.normalize3(orthogonal);
        return zmath.matFromQuat(zmath.f32x4(
            orthogonal[0],
            orthogonal[1],
            orthogonal[2],
            0.0,
        ));
    }
    const v = zmath.cross3(a, b);
    return zmath.matFromQuat(zmath.normalize4(zmath.f32x4(
        v[0],
        v[1],
        v[2],
        k + k_cos_theta,
    )));
}

pub fn getSphereTexCoord(p: zmath.Vec) [2]f32 {
    const theta = std.math.acos(-p[1]);
    const phi = std.math.atan2(f32, -p[2], p[0]) + std.math.pi;
    return .{ phi / (2.0 * std.math.pi), theta / std.math.pi };
}
