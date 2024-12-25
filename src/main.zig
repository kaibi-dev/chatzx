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
