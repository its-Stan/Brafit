const std = @import("std");

const testing = std.testing;
const eql = std.mem.eql;

const ContentError = error { NoFileProvided, UnclosedLoop, InexistantLoop };
const nb_cells = 32768;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();

    const filepath = args.next();

    if (filepath == null) {
        return ContentError.NoFileProvided;
    }

    const io = init.io;
    const allocator = init.arena.allocator();

    const content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        filepath.?,
        allocator,
        .unlimited
    );

    defer allocator.free(content);

    var readBuffer: [1024]u8 = undefined;
    var writeBuffer: [1024]u8 = undefined;

    var stdinReader = std.Io.File.stdin().reader(io, &readBuffer).interface;
    var stdoutWriter = std.Io.File.stdout().writer(io, &writeBuffer).interface;

    try interpret(
        content,
        allocator,
        &stdinReader,
        &stdoutWriter
    );
}

inline fn bounded_increment(value: usize, cap: usize) usize {
    if (value >= cap) { return 0; } else { return value + 1; }
}

inline fn bounded_decrement(value: usize, cap: usize) usize {
    if (value == 0) { return cap; } else { return value - 1; }
}

fn interpret(
    content: []const u8,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer
) !void {
    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(allocator);

    var array = std.mem.zeroes([nb_cells]u8);
    var pointer: usize = 0;
    var content_pos: usize = 0;

    while (content_pos < content.len) {
        switch (content[content_pos]) {
            '>' => pointer = bounded_increment(pointer, nb_cells - 1),
            '<' => pointer = bounded_decrement(pointer, nb_cells - 1),
            '+' => array[pointer] +%= 1,
            '-' => array[pointer] -%= 1,
            '.' => try writer.writeByte(array[pointer]),
            ',' => array[pointer] = try reader.takeByte(),
            '[' => if (array[pointer] == 0) {
                var loops: usize = 1;
                content_pos += 1;

                while (loops > 0 and content_pos < content.len) {
                    switch (content[content_pos]) {
                        '[' => loops += 1,
                        ']' => loops -= 1,
                        else => {},
                    }

                    if (loops > 0) {
                        content_pos += 1;
                    }
                }

                if (loops > 0) {
                    return ContentError.UnclosedLoop;
                }
            } else {
                try stack.append(allocator, content_pos);
            },
            ']' => if (array[pointer] == 0) {
                _ = stack.pop() orelse return ContentError.InexistantLoop;
            } else {
                content_pos = stack.getLastOrNull() orelse
                    return ContentError.InexistantLoop;
            },
            else => {},
        }

        content_pos += 1;
    }

    try writer.flush();
}

test "hello world" {
    const content =
        \\ ++++++++++
        \\ [>+++++++>++++++++++>+++>+<<<<-]
        \\ >++.>+.+++++++..+++.>++.<<
        \\ +++++++++++++++.>.+++.------.--------.>+.>.
    ;

    const allocator = testing.allocator;

    var internalBuffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    var bufferWriter = std.Io.Writer.fromArrayList(&internalBuffer);

    // Reader is not used in this test
    try interpret(
        content,
        allocator,
        std.Io.Reader.ending,
        &bufferWriter
    );

    internalBuffer = bufferWriter.toArrayList();
    defer internalBuffer.deinit(allocator);

    try testing.expect(eql(u8, internalBuffer.items, "Hello World!\n"));
}
