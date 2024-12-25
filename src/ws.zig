const std = @import("std");
const util = @import("util.zig");
const httpz = @import("httpz");
const websocket = httpz.websocket;

pub const std_options = std.Options{ .log_scope_levels = &[_]std.log.ScopeLevel{
    .{ .scope = .websocket, .level = .err },
} };

const Headers = struct {
    @"HX-Request": ?[]const u8,
    @"HX-Trigger": ?[]const u8,
    @"HX-Trigger-Name": ?[]const u8,
    @"HX-Target": ?[]const u8,
    @"HX-Current-URL": ?[]const u8,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
const alloc = gpa.allocator();
pub var clients = std.AutoHashMap(u32, Client).init(alloc);

pub const Handler = struct {
    pub const WebsocketHandler = Client;
};

pub const Client = struct {
    uid: u32,
    name: []const u8 = "",
    color: []const u8 = "#000000",
    conn: *websocket.Conn,

    const Context = struct {
        uid: u32,
    };

    // context is any abitrary data that you want, you'll pass it to upgradeWebsocket
    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        const client = Client{
            .conn = conn,
            .uid = ctx.uid,
        };
        try clients.put(client.uid, client);
        return client;
    }

    // at this point, it's safe to write to conn
    pub fn afterInit(self: *Client) !void {
        const str = try std.fmt.allocPrint(alloc,
            \\<div id="notifications" hx-swap-oob="beforeend" hx-ext="remove-me" class="col">
            \\<div id="notifications-user-id" remove-me="5s" class="row alert alert-info">{d} has joined</div>
            \\</div>
        , .{self.uid});
        const name = try std.fmt.allocPrint(alloc, "U{d}", .{self.uid});
        self.name = name;
        var iter = clients.valueIterator();
        while (iter.next()) |client| {
            client.conn.write(str) catch |err| {
                std.debug.print("error writing notification to client: {s}\n", .{@errorName(err)});
            };
        }
        return;
    }

    pub fn clientMessage(self: *Client, allocator: std.mem.Allocator, data: []const u8) !void {
        // echo back to client
        const formatted = try formatResponse(self, allocator, data);
        std.debug.print("clientMessage: {s}\n", .{formatted});

        var iter = clients.valueIterator();
        while (iter.next()) |client| {
            client.conn.write(formatted) catch |err| {
                std.debug.print("error writing to client: {s}\n", .{@errorName(err)});
            };
        }
        return;
    }

    pub fn close(self: *Client) void {
        const res = clients.remove(self.uid);
        if (res) {
            std.debug.print("client closed: {d}\n", .{self.uid});
        }
        return;
    }

    fn formatResponse(self: *Client, allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
        const json = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
        defer json.deinit();

        const msg = json.value.object.get("chat-input").?.string;

        const formatted = try std.fmt.allocPrint(allocator,
            \\<div id="chat-message" hx-swap-oob="beforeend" class="d-flex mb-3">
            \\    <div class="flex-grow-1">
            //        user + timestamp
            \\        <div id="chat-message-user-id" class="d-flex align-items-center mb-1">
            \\            <h5 class="me-2 mb-0 text-primary" style="color: {s}">{s}</h5>
            //            timestamp
            \\            <small class="text-muted">{s}</small>
            \\        </div>
            //        message
            \\        <div id="chat-message-text" class="bg-light rounded p-2">
            \\            <p class="mb-0">{s}</p>
            \\        </div>
            \\    </div>
            \\</div>
        , .{ self.color, self.name, util.getDateTimeString(), msg });
        return formatted;
    }
};

pub fn ws(_: Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const rand = std.crypto.random;
    const ctx = Client.Context{ .uid = rand.uintAtMost(u32, std.math.maxInt(u32)) };

    if (try httpz.upgradeWebsocket(Client, req, res, &ctx) == false) {
        res.status = 500;
        res.body = "invalid websocket";
    }
}
