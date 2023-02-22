const std = @import("std");
const Allocator = std.mem.Allocator;
const generated = @import("generated");
const cf = generated.conformance;
const test3 = generated.test_messages_proto3;
const test2 = generated.test_messages_proto2;
const Request = cf.ConformanceRequest;
const Response = cf.ConformanceResponse;
const pb = @import("protobuf");
const String = pb.extern_types.String;

pub const std_options = struct {
    pub const log_level = std.meta.stringToEnum(std.log.Level, @tagName(@import("build_options").log_level)).?;
};

pub fn main() !void {
    var total_runs: usize = 0;
    while (true) {
        const is_done = serveConformanceRequest() catch |e| {
            std.debug.panic("fatal: {s}", .{@errorName(e)});
        };
        if (is_done) break;
        total_runs += 1;
    }
    std.debug.print("conformance-zig: received EOF from test runner after {} tests\n", .{total_runs});
}

fn serializeTo(serializable: anytype, writer: anytype) !void {
    var countwriter = std.io.countingWriter(std.io.null_writer);
    try pb.protobuf.serialize(&serializable.base, countwriter.writer());
    try writer.writeIntLittle(u32, @intCast(u32, countwriter.bytes_written));
    try pb.protobuf.serialize(&serializable.base, writer);
}

fn debugReq(request: *Request, buf: []const u8) void {
    const tag = request.activeTag(.payload) orelse unreachable;
    const payload = switch (tag) {
        .payload__protobuf_payload => request.payload.protobuf_payload,
        .payload__json_payload => request.payload.json_payload,
        .payload__jspb_payload => request.payload.jspb_payload,
        .payload__text_payload => request.payload.text_payload,
        else => unreachable,
    };

    const payload_tagname = switch (tag) {
        .payload__protobuf_payload => "protobuf_payload",
        .payload__json_payload => "json_payload",
        .payload__jspb_payload => "jspb_payload",
        .payload__text_payload => "text_payload",
        else => unreachable,
    };
    std.debug.print("----\n", .{});
    std.debug.print("message_type            {s}\n", .{request.message_type});
    std.debug.print("requested_output_format {}\n", .{request.requested_output_format});
    std.debug.print("test_category           {}\n", .{request.test_category});
    if (tag == .payload__protobuf_payload)
        std.debug.print("payload                 {s} : {}({})\n", .{ payload_tagname, std.fmt.fmtSliceHexLower(payload.slice()), payload.len })
    else
        std.debug.print("payload                 {s} : {s}({})\n", .{ payload_tagname, payload.slice(), payload.len });
    std.debug.print("message                 {}\n", .{std.fmt.fmtSliceHexLower(buf)});
    std.debug.print("----\n", .{});
}

fn serveConformanceRequest() !bool {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allr = arena.allocator();
    var buf = std.ArrayList(u8).init(allr);

    const in_len = stdin.readIntNative(u32) catch |err| return switch (err) {
        error.EndOfStream => true,
        else => err,
    };

    const debug_request = false;
    if (debug_request) std.debug.print("\nin_len {} ", .{in_len});
    try buf.ensureTotalCapacity(in_len);
    buf.items.len = in_len;
    const amt = try stdin.read(buf.items);
    if (amt != in_len) return error.Amt;
    // if (debug_request) std.debug.print("message {}\n", .{std.fmt.fmtSliceHexLower(buf.items)});
    // std.debug.print("Request {}\n", .{Request});

    var ctx = pb.protobuf.context(buf.items, allr);
    var request_m = try ctx.deserialize(&Request.descriptor);
    const request = try request_m.as(Request);

    const response = runTest(allr, request) catch |e| {
        std.debug.print("error: runTest() {s}\n", .{@errorName(e)});
        return e;
    };
    if (debug_request) {
        if (response.activeTag(.result)) |tag| switch (tag) {
            .result__runtime_error => {
                std.debug.print("runtime_error: {s}\n", .{response.result.runtime_error});
                debugReq(request, buf.items);
            },
            .result__serialize_error => {
                std.debug.print("serialize_error: {s}\n", .{response.result.serialize_error});
                debugReq(request, buf.items);
            },
            .result__parse_error => {
                std.debug.print("parse_error: {s}\n", .{response.result.parse_error});
                debugReq(request, buf.items);
            },
            else => {},
        };
    }
    try serializeTo(response, stdout);
    return false;
}

fn runTest(allr: Allocator, request: *Request) !Response {
    var response = Response.init();
    // if (request.test_category == .JSON_TEST) {
    //     debugReq(request, &.{});
    // }
    if (std.mem.eql(u8, request.message_type.slice(), "conformance.FailureSet")) {
        var failure_set = cf.FailureSet.init();
        var failures = std.ArrayList([]const u8).init(allr);
        _ = failures;
        const all_failures: []const []const u8 = &.{
            // list of known failing tests to skip
            "Required.DurationProtoInputTooLarge.JsonOutput",
            "Required.DurationProtoInputTooSmall.JsonOutput",
            "Required.Proto2.ProtobufInput.RepeatedScalarMessageMerge.ProtobufOutput",
            "Required.Proto2.ProtobufInput.ValidDataMap.STRING.MESSAGE.MergeValue.ProtobufOutput",
            "Required.Proto2.ProtobufInput.ValidDataOneof.MESSAGE.Merge.ProtobufOutput",
            "Required.Proto3.ProtobufInput.RepeatedScalarMessageMerge.JsonOutput",
            "Required.Proto3.ProtobufInput.RepeatedScalarMessageMerge.ProtobufOutput",
            "Required.Proto3.ProtobufInput.ValidDataMap.STRING.ENUM.MissingDefault.JsonOutput",
            "Required.Proto3.ProtobufInput.ValidDataMap.STRING.MESSAGE.MergeValue.JsonOutput",
            "Required.Proto3.ProtobufInput.ValidDataMap.STRING.MESSAGE.MergeValue.ProtobufOutput",
            "Required.Proto3.ProtobufInput.ValidDataMap.STRING.MESSAGE.MissingDefault.JsonOutput",
            "Required.Proto3.ProtobufInput.ValidDataOneof.MESSAGE.Merge.JsonOutput",
            "Required.Proto3.ProtobufInput.ValidDataOneof.MESSAGE.Merge.ProtobufOutput",
            "Required.TimestampProtoInputTooLarge.JsonOutput",
            "Required.TimestampProtoInputTooSmall.JsonOutput",
        };

        for (all_failures) |f| {
            try failure_set.failure.append(allr, String.init(f));
        }
        var output = std.ArrayList(u8).init(allr);
        try pb.protobuf.serialize(&failure_set.base, output.writer());
        if (all_failures.len == 0)
            response.set(.result__skipped, String.init("Empty failure set"))
        else {
            failure_set.setPresent(.failure);
            response.set(.result__protobuf_payload, String.init(output.items));
        }
        return response;
    } else {
        var test_message: ?*pb.types.Message = null;
        if (request.activeTag(.payload)) |tag| switch (tag) {
            .payload__protobuf_payload => {
                var ctx = pb.protobuf.context(request.payload.protobuf_payload.slice(), allr);
                test_message = ctx.deserialize(&test3.TestAllTypesProto3.descriptor) catch |e| switch (e) {
                    error.EndOfStream => {
                        response.set(.result__parse_error, String.init("EOF"));
                        return response;
                    },
                    else => {
                        // std.debug.print("test_message.deserialize error {s}\n", .{@errorName(e)});
                        response.set(.result__parse_error, String.init(@errorName(e)));
                        return response;
                    },
                };
            },
            .payload__json_payload => {
                response.set(.result__skipped, String.init("TODO json_payload"));
                // var tokens = std.json.TokenStream.init(request.payload.json_payload);
                // test_message = try std.json.parse(test3.TestAllTypesProto3, &tokens, .{ .ignore_unknown_fields = true });
                return response;
            },
            .payload__jspb_payload => {
                response.set(.result__skipped, String.init("TODO jspb_payload"));
                return response;
            },
            .payload__text_payload => {
                response.set(.result__skipped, String.init("TODO text_payload"));
                return response;
            },
            else => unreachable,
        };
        switch (request.requested_output_format) {
            .UNSPECIFIED => return error.InvalidArgument_UnspecifiedOutputFormat,
            .PROTOBUF => {
                // response.set(.result__skipped, String.init("TODO PB output"));
                var output = std.ArrayList(u8).init(allr);
                try pb.protobuf.serialize(test_message.?, output.writer());
                response.set(.result__protobuf_payload, String.init(try output.toOwnedSlice()));
            },
            .JSON => {
                // response.set(.result__skipped, String.init("TODO JSON output"));
                var output = std.ArrayList(u8).init(allr);
                try pb.json.serialize(test_message.?, output.writer(), .{});
                response.set(
                    .result__json_payload,
                    String.init(try output.toOwnedSlice()),
                );
            },
            .JSPB => {
                response.set(.result__skipped, String.init("TODO JSPB output"));
            },
            .TEXT_FORMAT => {
                response.set(.result__skipped, String.init("TODO TEXT_FORMAT output"));
            },
        }
    }

    return response;
}
