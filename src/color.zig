const zmath = @import("zmath");
const Texture = @import("texture.zig").Texture;

pub const Color = union(enum) {
    vec: zmath.Vec,
    texture: *Texture,
};
