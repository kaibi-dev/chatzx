const std = @import("std");
const httpz = @import("httpz");
const ws = @import("ws.zig");

const PORT = 8080;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server(ws.Handler).init(allocator, .{
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
    router.get("/modal", modal, .{});
    router.get("/chat", ws.ws, .{});

    std.debug.print("Server listening on port {d}\n", .{PORT});

    try server.listen();
}

fn indexHTML(_: ws.Handler, _: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("html/index.html");
}

fn click(_: ws.Handler, _: *httpz.Request, res: *httpz.Response) !void {
    std.debug.print("CLICK\n", .{});
    res.body =
        \\CLICKED
    ;
}

fn modal(_: ws.Handler, _: *httpz.Request, res: *httpz.Response) !void {
    const alloc = std.heap.page_allocator;
    var buf: [1024]u8 = undefined;
    var buf_index: usize = 0;

    var iter = ws.clients.keyIterator();
    while (iter.next()) |id| {
        const str = try std.fmt.allocPrint(alloc,
            \\<div id="modal-user-id" class="row">{d}</div>
        , .{id.*});
        if (buf_index + str.len > buf.len) {
            return error.BufferTooSmall;
        }

        std.mem.copyForwards(u8, buf[buf_index..], str);
        buf_index += str.len;
    }
    res.body = try std.fmt.allocPrint(alloc,
        \\\<div class="modal-dialog modal-dialog-centered">
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
