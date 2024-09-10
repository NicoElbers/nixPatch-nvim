pub const Plugin = struct {
    pname: []const u8,
    version: []const u8,
    path: []const u8,

    tag: Tag,
    url: []const u8,

    const Tag = enum {
        /// url field in undefined
        UrlNotFound,

        /// url field is github url
        GithubUrl,

        /// url field is non specific url
        GitUrl,
    };

    pub fn deinit(self: Plugin, alloc: Allocator) void {
        alloc.free(self.pname);
        alloc.free(self.version);
        alloc.free(self.path);

        if (self.tag == .UrlNotFound) return;

        alloc.free(self.url);
    }

    pub fn deinitPlugins(slice: []const Plugin, alloc: Allocator) void {
        for (slice) |plugin| {
            plugin.deinit(alloc);
        }
        alloc.free(slice);
    }
};

pub const Substitution = struct {
    from: []const u8,
    to: []const u8,
    tag: Tag,

    const Tag = union(enum) {
        /// Extra data is the pname
        url: []const u8,
        /// Extra data is the key
        string: ?[]const u8,
        raw,
    };

    pub fn initUrlSub(
        alloc: Allocator,
        from: []const u8,
        to: []const u8,
        pname: []const u8,
    ) !Substitution {
        return Substitution{
            .from = try alloc.dupe(u8, from),
            .to = try alloc.dupe(u8, to),
            .tag = .{ .url = try alloc.dupe(u8, pname) },
        };
    }

    pub fn initStringSub(
        alloc: Allocator,
        from: []const u8,
        to: []const u8,
        key: ?[]const u8,
    ) !Substitution {
        return Substitution{
            .from = try alloc.dupe(u8, from),
            .to = try alloc.dupe(u8, to),
            .tag = .{ .string = if (key) |k| try alloc.dupe(u8, k) else null },
        };
    }

    pub fn deinit(self: Substitution, alloc: Allocator) void {
        alloc.free(self.to);
        alloc.free(self.from);
        switch (self.tag) {
            .raw => {},
            .url => |pname| alloc.free(pname),
            .string => |key| {
                if (key) |k| {
                    alloc.free(k);
                }
            },
        }
    }

    pub fn deinitSubs(slice: []const Substitution, alloc: Allocator) void {
        for (slice) |sub| {
            sub.deinit(alloc);
        }
        alloc.free(slice);
    }
};

const Allocator = @import("std").mem.Allocator;
