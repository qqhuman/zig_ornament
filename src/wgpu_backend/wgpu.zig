const webgpu = @import("webgpu.zig");

pub const SubmissionIndex = u32;

pub const BindGroupEntryExtras = struct {
    chain: webgpu.ChainedStruct,
    buffers: ?[*]webgpu.Buffer = null,
    buffer_count: usize = 0,
    samplers: ?[*]webgpu.Sampler = null,
    sampler_count: usize = 0,
    texture_views: ?[*]webgpu.TextureView = null,
    texture_view_count: usize = 0,
};

pub const BindGroupLayoutEntryExtras = struct {
    chain: webgpu.ChainedStruct,
    count: usize,
};

pub const WrappedSubmissionIndex = extern struct {
    queue: webgpu.Queue,
    submission_index: SubmissionIndex,
};

pub extern fn wgpuDevicePoll(device: webgpu.Device, wait: bool, wrapped_submission_index: ?*const WrappedSubmissionIndex) bool;
