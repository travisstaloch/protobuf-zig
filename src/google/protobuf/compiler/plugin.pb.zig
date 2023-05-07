//!
//! this file was originally adapted from https://github.com/protobuf-c/protobuf-c/blob/master/protobuf-c/protobuf-c.h
//! by running `$ zig translate-c` on this file and then doing lots and lots and lots and lots of editing.
//!
//! it is an effort to bootstrap the project and should eventually be generated
//! from https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/descriptor.proto
//! and https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/compiler/plugin.proto
//!

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const pb = @import("protobuf");
const extern_types = pb.extern_types;
const String = extern_types.String;
const ListMut = extern_types.ListMut;
const types = pb.types;
const ListMutScalar = extern_types.ListMutScalar;
const MessageMixins = types.MessageMixins;
const Message = types.Message;
const FieldDescriptor = types.FieldDescriptor;
const FileDescriptorProto = pb.descriptor.FileDescriptorProto;

pub const Version = extern struct {
    base: Message,
    major: i32 = 0,
    minor: i32 = 0,
    patch: i32 = 0,
    suffix: String = String.initEmpty(),

    pub const field_ids = [_]c_uint{ 1, 2, 3, 4 };
    pub const opt_field_ids = [_]c_uint{ 1, 2, 3, 4 };
    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [4]FieldDescriptor{
        FieldDescriptor.init(
            "major",
            1,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "major"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "minor",
            2,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "minor"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "patch",
            3,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "patch"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "suffix",
            4,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(Version, "suffix"),
            null,
            null,
            0,
        ),
    };
};

pub const CodeGeneratorRequest = extern struct {
    base: Message,
    file_to_generate: ListMutScalar(String) = .{},
    parameter: String = String.initEmpty(),
    proto_file: ListMut(*FileDescriptorProto) = .{},
    compiler_version: *Version = undefined,

    comptime {
        // @compileLog(@sizeOf(CodeGeneratorRequest));
        assert(@sizeOf(CodeGeneratorRequest) == 112);
        // @compileLog(@offsetOf(CodeGeneratorRequest, "proto_file"));
        assert(@offsetOf(CodeGeneratorRequest, "proto_file") == 0x50); //  == 80
    }

    pub const field_ids = [_]c_uint{ 1, 2, 15, 3 };
    pub const opt_field_ids = [_]c_uint{ 2, 3 };
    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [4]FieldDescriptor{
        FieldDescriptor.init(
            "file_to_generate",
            1,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorRequest, "file_to_generate"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "parameter",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorRequest, "parameter"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "proto_file",
            15,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorRequest, "proto_file"),
            &FileDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "compiler_version",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorRequest, "compiler_version"),
            &Version.descriptor,
            null,
            0,
        ),
    };
};

pub const CodeGeneratorResponse = extern struct {
    base: Message,
    @"error": String = String.empty,
    supported_features: u64 = 0,
    file: ListMut(*CodeGeneratorResponse.File) = .{},

    pub const field_ids = [_]c_uint{ 1, 2, 15 };
    pub const opt_field_ids = [_]c_uint{ 1, 2 };
    pub const is_map_entry = false;

    pub usingnamespace MessageMixins(@This());
    pub const field_descriptors = [_]FieldDescriptor{
        FieldDescriptor.init(
            "error",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorResponse, "error"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "supported_features",
            2,
            .LABEL_OPTIONAL,
            .TYPE_UINT64,
            @offsetOf(CodeGeneratorResponse, "supported_features"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "file",
            15,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorResponse, "file"),
            &CodeGeneratorResponse.File.descriptor,
            null,
            0,
        ),
    };

    pub const File = extern struct {
        base: Message,
        name: String = String.empty,
        insertion_point: String = String.empty,
        content: String = String.empty,
        generated_code_info: *pb.descriptor.GeneratedCodeInfo = undefined,

        pub const field_ids = [_]c_uint{ 1, 2, 15, 16 };
        pub const opt_field_ids = [_]c_uint{ 1, 2, 15, 16 };
        pub const is_map_entry = false;

        pub usingnamespace MessageMixins(@This());
        pub const field_descriptors = [_]FieldDescriptor{
            FieldDescriptor.init(
                "name",
                1,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(CodeGeneratorResponse.File, "name"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "insertion_point",
                2,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(CodeGeneratorResponse.File, "insertion_point"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "content",
                15,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(CodeGeneratorResponse.File, "content"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "generated_code_info",
                16,
                .LABEL_OPTIONAL,
                .TYPE_MESSAGE,
                @offsetOf(CodeGeneratorResponse.File, "generated_code_info"),
                &pb.descriptor.GeneratedCodeInfo.descriptor,
                null,
                0,
            ),
        };
    };
    pub const Feature = enum(i32) {
        FEATURE_NONE = 0,
        FEATURE_PROTO3_OPTIONAL = 1,

        pub usingnamespace types.EnumMixins(@This());
    };
};
