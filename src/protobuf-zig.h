#include <stddef.h>
#include <stdint.h>

#ifndef PROTOBUF_ZIG_H
#define PROTOBUF_ZIG_H

static const uint32_t SERVICE_DESCRIPTOR_MAGIC = 0x14159bc3;
static const uint32_t MESSAGE_DESCRIPTOR_MAGIC = 0x28aaeef9;
static const uint32_t ENUM_DESCRIPTOR_MAGIC = 0x114315af;
#define PbZigfalse 0
#define PbZigtrue 1

#define LIST_DEF(name, T) \
  typedef struct name {   \
    size_t len;           \
    T ptr;                \
  } name

#define ARRAY_SIZE(x) ((sizeof x) / (sizeof *x))

#define LIST_INIT(items) \
  { ARRAY_SIZE(items), (items) }

#define STRING_INIT(items) \
  { ARRAY_SIZE(items) - 1, (items) }

typedef struct PbZigMessageDescriptor PbZigMessageDescriptor;
typedef struct PbZigFieldDescriptor PbZigFieldDescriptor;
typedef struct PbZigEnumDescriptor PbZigEnumDescriptor;
typedef struct PbZigEnumValue PbZigEnumValue;
typedef struct PbZigUnknownField PbZigUnknownField;
typedef struct PbZigMessage PbZigMessage;

LIST_DEF(PbZigString, char *);
LIST_DEF(PbZigConstString, const char *);
LIST_DEF(PbZigStringList, PbZigString);
LIST_DEF(int32_tList, int32_t);
LIST_DEF(int64_tList, int64_t);
LIST_DEF(uint32_tList, uint32_t);
LIST_DEF(uint64_tList, uint64_t);
LIST_DEF(floatList, float);
LIST_DEF(doubleList, double);
LIST_DEF(uint8_tList, uint8_t);
LIST_DEF(PbZigFieldDescriptorList, const PbZigFieldDescriptor *);
LIST_DEF(PbZigEnumValueList, const PbZigEnumValue *);

#define PbZigString_empty (PbZigString){0, ""}

typedef void (*PbZigMessageInit)(PbZigMessage *);

typedef enum {
  LABEL_REQUIRED,
  LABEL_OPTIONAL,
  LABEL_REPEATED,
  LABEL_NONE,
} PbZigLabel;

typedef enum {
  TYPE_INT32,
  TYPE_SINT32,
  TYPE_SFIXED32,
  TYPE_INT64,
  TYPE_SINT64,
  TYPE_SFIXED64,
  TYPE_UINT32,
  TYPE_FIXED32,
  TYPE_UINT64,
  TYPE_FIXED64,
  TYPE_FLOAT,
  TYPE_DOUBLE,
  TYPE_BOOL,
  TYPE_ENUM,
  TYPE_STRING,
  TYPE_BYTES,
  TYPE_MESSAGE,
} PbZigType;

typedef enum {
  FIELD_FLAG_PACKED    = (1 << 0),
  FIELD_FLAG_DEPRECATED  = (1 << 1),
  FIELD_FLAG_ONEOF   = (1 << 2),
} PbZigFieldFlag;


struct PbZigMessageDescriptor {
  uint32_t magic;
  PbZigString name;
  PbZigString short_name;
  PbZigString c_name;
  PbZigString package_name;
  size_t sizeof_message;
  PbZigFieldDescriptorList fields;
  // const unsigned *fields_sorted_by_name;
  // unsigned n_field_ranges;
  // const PbZigIntRange  *field_ranges;
  PbZigMessageInit message_init;
  void *reserved1;
  void *reserved2;
  void *reserved3;
};

struct PbZigFieldDescriptor {
  PbZigConstString name;
  uint32_t id;
  PbZigLabel label;
  PbZigType type;
  // uint32_t quantifier_offset;
  uint32_t offset;
  const void *descriptor;
  const void *default_value;
  uint32_t flags;
  uint32_t reserved_flags;
  void *reserved2;
  void *reserved3;
};

struct PbZigEnumValue {
  PbZigString name;
  PbZigString zig_name;
  int32_t value;
};

struct PbZigEnumDescriptor {
  uint32_t magic;
  PbZigString name;
  PbZigString short_name;
  PbZigString c_name;
  PbZigString package_name;
  PbZigEnumValueList values;
  void *reserved1;
  void *reserved2;
  void *reserved3;
  void *reserved4;
};

struct PbZigUnknownField {
  uint32_t tag;
  size_t len;
  uint8_t *data;
};

struct PbZigMessage {
  const PbZigMessageDescriptor *descriptor;
  unsigned n_unknown_fields;
  PbZigUnknownField *unknown_fields;
};
#define PBZIG_MESSAGE_INIT(descriptor) \
  { descriptor, 0, NULL }

#endif  // PROTOBUF_ZIG_H
