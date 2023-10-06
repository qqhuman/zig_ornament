const webgpu = @import("webgpu.zig");

pub const SubmissionIndex = u32;
pub const WrappedSubmissionIndex = extern struct { queue: webgpu.Queue, submission_index: SubmissionIndex };
pub extern fn wgpuDevicePoll(device: webgpu.Device, wait: bool, wrapped_submission_index: ?*const WrappedSubmissionIndex) bool;
