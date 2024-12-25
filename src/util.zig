const ctime = @cImport(@cInclude("time.h"));

pub fn getDateTimeString() []const u8 {
    var dt_str_buf: [40]u8 = undefined;
    const t = ctime.time(null);
    const lt = ctime.localtime(&t);
    const format = "%m/%d/%y %I:%M %p %Z";
    const dt_str_len = ctime.strftime(&dt_str_buf, dt_str_buf.len, format, lt);

    return dt_str_buf[0..dt_str_len];
}
