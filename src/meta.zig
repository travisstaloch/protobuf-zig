const std = @import("std");
const mem = std.mem;

pub const Field = union(enum) {
    struct_field: std.builtin.Type.StructField,
    union_field: std.builtin.Type.UnionField,

    pub fn ty(comptime f: Field) type {
        return switch (f) {
            .struct_field => |sf| sf.type,
            .union_field => |sf| sf.type,
        };
    }
    pub fn name(comptime f: Field) []const u8 {
        return switch (f) {
            .struct_field => |sf| sf.name,
            .union_field => |sf| sf.name,
        };
    }
};

/// copy of std.meta.FieldEnum which also includes the field names of any
/// union fields in T.  This is non-recursive and only for immediate children.
///   given struct{a: u8, b: union{c, d}}
///   returns enum{a, c, d};
pub fn FieldEnum(comptime T: type) type {
    const EnumField = std.builtin.Type.EnumField;
    var fs: []const EnumField = &.{};
    inline for (std.meta.fields(T)) |field| {
        const fieldinfo = @typeInfo(field.type);
        // if (isStringIn(field.name, exclude_fields)) continue;
        switch (fieldinfo) {
            .Union => inline for (fieldinfo.Union.fields) |ufield| {
                fs = fs ++ [1]EnumField{.{
                    .name = field.name ++ "__" ++ ufield.name,
                    .value = fs.len,
                }};
            },
            else => fs = fs ++ [1]EnumField{.{
                .name = field.name,
                .value = fs.len,
            }},
        }
    }
    return @Type(.{ .Enum = .{
        .tag_type = std.math.IntFittingRange(0, fs.len -| 1),
        .fields = fs,
        .decls = &.{},
        .is_exhaustive = true,
    } });
}

pub fn fields(comptime T: type) switch (@typeInfo(T)) {
    .Struct => []const Field,
    else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
} {
    if (@typeInfo(T) != .Struct)
        @compileError("Expected struct type, found '" ++ @typeName(T) ++ "'");

    var fs: []const Field = &.{};
    inline for (std.meta.fields(T)) |field| {
        const fieldinfo = @typeInfo(field.type);
        switch (fieldinfo) {
            .Union => inline for (fieldinfo.Union.fields) |ufield| {
                var uf = ufield;
                uf.name = field.name ++ "__" ++ ufield.name;
                fs = fs ++ [1]Field{.{ .union_field = uf }};
            },
            else => fs = fs ++ [1]Field{.{ .struct_field = field }},
        }
    }
    return fs;
}

/// copy of std.meta.fieldInfo
pub fn fieldInfo(comptime T: type, comptime field: FieldEnum(T)) switch (@typeInfo(T)) {
    .Struct => Field,
    // .Union => std.builtin.Type.UnionField,
    // .ErrorSet => std.builtin.Type.Error,
    // .Enum => std.builtin.Type.EnumField,
    else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
} {
    return fields(T)[@enumToInt(field)];
}

/// copy of std.meta.fieldIndex
pub fn fieldIndex(comptime T: type, comptime name: []const u8) ?comptime_int {
    inline for (fields(T)) |field, i| {
        if (mem.eql(u8, field.name(), name))
            return i;
    }
    return null;
}

/// copy of std.meta.FieldType but adapted to work with union field tagnames of
/// the form `union_field__tagname`
pub fn FieldType(comptime T: type, comptime field: FieldEnum(T)) type {
    if (@typeInfo(T) != .Struct and @typeInfo(T) != .Union) {
        @compileError("Expected struct or union, found '" ++ @typeName(T) ++ "'");
    }

    return fieldInfo(T, field).ty();
}
