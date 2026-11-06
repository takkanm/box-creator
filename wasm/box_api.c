/* The one function JavaScript calls. Ruby bytecode is embedded in the binary. */
#include <stdlib.h>
#include <string.h>
#include <emscripten/emscripten.h>
#include <mruby.h>
#include <mruby/irep.h>
#include <mruby/string.h>
#include <mruby/variable.h>

extern const uint8_t box_irep[];

static mrb_state *mrb = NULL;

static char *copy_bytes(const char *src, size_t len)
{
  char *dst = malloc(len + 1);
  if (dst) {
    memcpy(dst, src, len);
    dst[len] = '\0';
  }
  return dst;
}

static char *fail_with(const char *message, int *out_len)
{
  size_t len = strlen(message);
  *out_len = -(int)len;
  return copy_bytes(message, len);
}

static char *take_exception(int *out_len)
{
  mrb_value text = mrb_funcall(mrb, mrb_obj_value(mrb->exc), "inspect", 0);
  char *result;
  mrb->exc = NULL;
  *out_len = -(int)RSTRING_LEN(text);
  result = copy_bytes(RSTRING_PTR(text), RSTRING_LEN(text));
  return result;
}

/*
 * params: "key=value" lines. part: 0 base, 1 lid, 2 ring, 3 info.
 * Returns a malloc'ed buffer the caller frees. *out_len is its length, or the
 * negated length of an error message when Ruby raised.
 */
EMSCRIPTEN_KEEPALIVE
char *box_generate(const char *params, int part, int *out_len)
{
  int arena;
  mrb_value module, input, result;
  char *bytes;

  if (mrb == NULL) {
    mrb = mrb_open();
    if (mrb == NULL) {
      return fail_with("mrb_open failed", out_len);
    }
    mrb_load_irep(mrb, box_irep);
    if (mrb->exc) {
      return take_exception(out_len);
    }
  }

  arena = mrb_gc_arena_save(mrb);
  module = mrb_obj_value(mrb_module_get(mrb, "BoxCreator"));
  input = mrb_str_new_cstr(mrb, params);
  result = mrb_funcall(mrb, module, "generate", 2, input, mrb_fixnum_value(part));
  if (mrb->exc) {
    bytes = take_exception(out_len);
  }
  else {
    *out_len = (int)RSTRING_LEN(result);
    bytes = copy_bytes(RSTRING_PTR(result), RSTRING_LEN(result));
  }
  mrb_gc_arena_restore(mrb, arena);
  return bytes;
}
