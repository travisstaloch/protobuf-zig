#include <stdint.h>
#include <stddef.h>

#ifndef PROTOBUF_ZIG_H
#define PROTOBUF_ZIG_H


#define LIST_DEF(name, T) typedef struct name name;\
struct name {size_t len; T ptr}
#define ARRAY_SIZE(x) ((sizeof x) / (sizeof *x))
#define LIST_INIT(items) { ARRAY_SIZE(items), (items) }
#define STRING_INIT(items) { ARRAY_SIZE(items)-1, (items) }


typedef struct PbZigMessageDescriptor PbZigMessageDescriptor;
typedef struct PbZigFieldDescriptor PbZigFieldDescriptor;
typedef struct PbZigUnknownField PbZigUnknownField;
typedef struct PbZigMessage PbZigMessage;

LIST_DEF(PbZigString, char *);
LIST_DEF(PbZigConstString, const char *);
LIST_DEF(PbZigFieldDescriptorList, const PbZigFieldDescriptor *);

typedef void (*PbZigMessageInit)(PbZigMessage *);

struct PbZigMessageDescriptor {
  uint32_t magic;
  PbZigString name;
  PbZigString short_name;
  PbZigString c_name;
  PbZigString package_name;
  size_t sizeof_message;
  // unsigned n_fields;
  // const FieldDescriptor *fields;
  PbZigFieldDescriptorList fields;
  // const unsigned *fields_sorted_by_name;
  // unsigned n_field_ranges;
  // const IntRange  *field_ranges;
  PbZigMessageInit message_init;
  void *reserved1;
  void *reserved2;
  void *reserved3;
};

struct PbZigFieldDescriptor {
  PbZigString name;
  uint32_t  id;
  unsigned  offset;
  const void  *descriptor;
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
#define MESSAGE_INIT(descriptor) { descriptor, 0, NULL }

#endif //PROTOBUF_ZIG_H
