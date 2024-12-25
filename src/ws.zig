const std = @import("std");
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

const alloc = std.heap.page_allocator;
pub var clients = std.AutoHashMap(u32, Client).init(alloc);

pub const Handler = struct {
    pub const WebsocketHandler = Client;
};

pub const Client = struct {
    user_id: u32,
    conn: *websocket.Conn,

    const Context = struct {
        user_id: u32,
    };

    // context is any abitrary data that you want, you'll pass it to upgradeWebsocket
    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        const client = Client{
            .conn = conn,
            .user_id = ctx.user_id,
        };
        try clients.put(client.user_id, client);
        return client;
    }

    // at this point, it's safe to write to conn
    pub fn afterInit(self: *Client) !void {
        var buf: [1024]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf,
            \\<div id="notifications" hx-swap-oob="beforeend" hx-ext="remove-me" class="col">
            \\<div id="notifications-user-id" remove-me="5s" class="row alert alert-info">{d} has joined</div>
            \\</div>
        , .{self.user_id});
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
        const res = clients.remove(self.user_id);
        if (res) {
            std.debug.print("client closed: {d}\n", .{self.user_id});
        }
        return;
    }

    fn formatResponse(self: *Client, allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
        const json = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
        defer json.deinit();

        const msg = json.value.object.get("chat-message").?.string;
        const formatted = try std.fmt.allocPrint(allocator,
            \\<div id="chat-message" hx-swap-oob="beforeend" class="d-flex mb-3">
            \\    <div class="flex-grow-1">
            //        user + timestamp
            \\        <div id="chat-message-user-id" class="d-flex align-items-center mb-1">
            \\            <h5 class="me-2 mb-0 text-primary">{d}</h5>
            \\            <small class="text-muted">{d}</small>
            \\        </div>
            //        message
            \\        <div id="chat-message-text" class="bg-light rounded p-2">
            \\            <p class="mb-0">{s}</p>
            \\        </div>
            \\    </div>
            \\</div>
        , .{ self.user_id, std.time.timestamp(), msg });
        return formatted;
    }
};

pub fn ws(_: Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const rand = std.crypto.random;
    const ctx = Client.Context{ .user_id = rand.uintAtMost(u32, std.math.maxInt(u32)) };

    if (try httpz.upgradeWebsocket(Client, req, res, &ctx) == false) {
        res.status = 500;
        res.body = "invalid websocket";
    }
}
