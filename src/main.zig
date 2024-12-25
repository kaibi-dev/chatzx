const std = @import("std");
const httpz = @import("httpz");
const ws = @import("ws.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // We pass a "void" handler. This is the simplest, but limits what we can do
    // The last parameter is an instance of our handler. Since we have
    // a void handler, we pass a void value: i.e. {}.
    var server = try httpz.Server(ws.Handler).init(allocator, .{
        .port = 8080,
        .request = .{
            // httpz has a number of tweakable configuration settings (see readme)
            // by default, it won't read form data. We need to configure a max
            // field count (since one of our examples reads form data)
            .max_form_count = 20,
        },
    }, ws.Handler{});
    defer server.deinit();

    // ensures a clean shutdown, finishing off any existing requests
    // see 09_shutdown.zig for how to to break server.listen with an interrupt
    defer server.stop();

    var router = server.router(.{});

    router.get("/", indexHTML, .{});
    router.get("/click", click, .{});
    router.get("/modal", modal, .{});
    router.get("/chat", ws.ws, .{});

    std.debug.print("Server listening on port {d}\n", .{8080});

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
