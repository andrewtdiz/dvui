pub const VersionTracker = struct {
    value: u64 = 0,

    pub fn next(self: *VersionTracker) u64 {
        self.value +%= 1;
        return self.value;
    }

    pub fn current(self: *const VersionTracker) u64 {
        return self.value;
    }
};
