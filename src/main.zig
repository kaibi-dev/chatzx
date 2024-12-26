const std = @import("std");
const httpz = @import("httpz");
const ws = @import("ws.zig");

const PORT = 8080;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();

var click_count: usize = 0;

pub fn main() !void {
    var server = try httpz.Server(ws.Handler).init(alloc, .{
        .port = PORT,
        .request = .{
            .max_form_count = 20,
        },
        .address = "0.0.0.0",
    }, ws.Handler{});
    defer server.deinit();

    defer server.stop();

    var router = server.router(.{});

    router.get("/", indexHTML, .{});
    router.get("/click", click, .{});
    router.get("/online", online, .{});
    router.get("/chat", ws.ws, .{});
    router.get("/settings", settings, .{});
    router.post("/color", ws.colorChange, .{});
    router.post("/name", ws.nameChange, .{});

    std.debug.print("Server listening on port {d}\n", .{PORT});

    try server.listen();
}

fn indexHTML(_: ws.Handler, _: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("html/index.html");
}

fn click(_: ws.Handler, _: *httpz.Request, res: *httpz.Response) !void {
    click_count += 1;
    res.body = try std.fmt.allocPrint(alloc,
        \\CLICK {d}
    , .{click_count});
}

fn online(_: ws.Handler, _: *httpz.Request, res: *httpz.Response) !void {
    var buf = try alloc.alloc(u8, 1024);
    var buf_index: usize = 0;

    var iter = ws.clients.valueIterator();
    while (iter.next()) |client| {
        const str = try std.fmt.allocPrint(alloc,
            \\<div id="online-user-id" class="row" style="color: {s}">{s}</div>
        , .{ client.*.color, client.*.name });
        if (buf_index + str.len > buf.len) {
            return error.BufferTooSmall;
        }

        std.mem.copyForwards(u8, buf[buf_index..], str);
        buf_index += str.len;
    }
    res.body = try std.fmt.allocPrint(alloc,
        \\<div class="modal-dialog modal-dialog-centered">
        \\<div class="modal-content">
        \\<div class="modal-header">
        \\<h5 class="modal-title">Online Users</h5>
        \\</div>
        \\<div class="modal-body">
        \\{s}
        \\</div>
        \\<div class="modal-footer">
        \\<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
        \\</div>
        \\</div>
        \\</div>
    , .{buf[0..buf_index]});
}

fn settings(_: ws.Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const uid = req.header("uid") orelse return error.MissingUID;

    const client = ws.clients.get(std.fmt.parseInt(u32, uid, 0) catch 0) orelse return error.ClientNotFound;

    res.body = try std.fmt.allocPrint(alloc,
        \\<div class="modal-dialog modal-dialog-centered">
        \\<div class="modal-content">
        \\<div class="modal-header">
        \\<h5 class="modal-title">Settings</h5>
        \\</div>
        \\<div class="modal-body">
        \\<div class="row">
        \\<h4>Name:</h4>
        \\<form>
        \\<input id="name-input" name="name-input" type="text" value="{s}" hx-ext="debug">
        \\<button type="button" class="btn btn-primary" hx-post="/name" hx-trigger="click" hx-swap="none">Save</button>
        \\</form>
        \\</div>
        \\<form>
        \\<input id="color-input" name="color-input" type="color" value="{s}" hx-post="/color" hx-trigger="change">
        \\</form>
        \\</div>
        \\<div class="modal-footer">
        \\<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
        \\</div>
        \\</div>
        \\</div>
    , .{ client.name, client.color });
}
