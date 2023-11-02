const zmath = @import("zmath");

pub const Aabb = struct {
    const Self = @This();
    min: zmath.Vec,
    max: zmath.Vec,

    pub fn init(min: zmath.Vec, max: zmath.Vec) Self {
        return .{ .min = min, .max = max };
    }

    pub fn grow(self: *Self, p: zmath.Vec) void {
        self.min = zmath.min(self.min, p);
        self.max = zmath.max(self.max, p);
    }

    pub fn transform(m: zmath.Mat, aabb: Aabb) Aabb {
        var p0 = aabb.min;
        var p1 = zmath.f32x4(aabb.max[0], aabb.min[1], aabb.min[2], 1.0);
        var p2 = zmath.f32x4(aabb.min[0], aabb.max[1], aabb.min[2], 1.0);
        var p3 = zmath.f32x4(aabb.min[0], aabb.min[1], aabb.max[2], 1.0);
        var p4 = zmath.f32x4(aabb.min[0], aabb.max[1], aabb.max[2], 1.0);
        var p5 = zmath.f32x4(aabb.max[0], aabb.max[1], aabb.min[2], 1.0);
        var p6 = zmath.f32x4(aabb.max[0], aabb.min[1], aabb.max[2], 1.0);
        var p7 = aabb.max;

        p0 = zmath.mul(p0, m);
        p1 = zmath.mul(p1, m);
        p2 = zmath.mul(p2, m);
        p3 = zmath.mul(p3, m);
        p4 = zmath.mul(p4, m);
        p5 = zmath.mul(p5, m);
        p6 = zmath.mul(p6, m);
        p7 = zmath.mul(p7, m);

        var result = Aabb.init(p0, p0);
        result.grow(p1);
        result.grow(p2);
        result.grow(p3);
        result.grow(p4);
        result.grow(p5);
        result.grow(p6);
        result.grow(p7);
        return result;
    }
};
