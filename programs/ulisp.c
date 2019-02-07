/* uLisp Zero 1.1 - www.ulisp.com
   David Johnson-Davies - www.technoblogy.com - 18th May 2017

   Licensed under the MIT license: https://opensource.org/licenses/MIT
*/

#include <stdint.h>

// C Macros

#define NULL               0
#define nil                NULL
#define car(x)             (((object *) (x))->car)
#define cdr(x)             (((object *) (x))->cdr)

#define first(x)           (((object *) (x))->car)
#define second(x)          (car(cdr(x)))
#define cddr(x)            (cdr(cdr(x)))
#define third(x)           (car(cdr(cdr(x))))

#define push(x, y)         ((y) = cons((x),(y)))
#define pop(y)             ((y) = cdr(y))

#define symbolp(x)         ((x)->type == SYMBOL)

#define mark(x)            (car(x) = (object *)(((uintptr_t)(car(x))) | MARKBIT))
#define unmark(x)          (car(x) = (object *)(((uintptr_t)(car(x))) & ~MARKBIT))
#define marked(x)          ((((uintptr_t)(car(x))) & MARKBIT) != 0)
#define MARKBIT            1

typedef struct {
	uint32_t state[14];
} jmp_buf[1];

extern "C" int setjmp(jmp_buf env);
extern "C" void longjmp(jmp_buf env, int val);

// Constants

enum type { ZERO=0, SYMBOL=2, PAIR=4 };  // PAIR must be last
enum token { UNUSED, BRA, KET, QUO, DOT };

enum function { SYMBOLS, NIL, TEE, LAMBDA, SPECIAL_FORMS, QUOTE, DEFUN, DEFVAR, SETQ, IF, FUNCTIONS, NOT,
NULLFN, CONS, ATOM, LISTP, CONSP, SYMBOLP, EQ, CAR, CDR, EVAL, GLOBALS, LOCALS, ENDFUNCTIONS };

// Typedefs

typedef unsigned int symbol_t;

typedef struct sobject {
  union {
    struct {
      sobject *car;
      sobject *cdr;
    };
    struct {
      unsigned int type;
      union {
        symbol_t name;
        int integer;
      };
    };
  };
} object;

typedef object *(* const fn_ptr_type)(object *, object *);

typedef struct {
  char const * string;
  fn_ptr_type fptr;
  int min;
  int max;
} tbl_entry_t;

// Workspace - sizes in bytes
#define WORDALIGNED __attribute__((aligned (2)))
#define BUFFERSIZE 18
#define WORKSPACESIZE 1000            /* Cells (4*bytes) */

object Workspace[WORKSPACESIZE] WORDALIGNED;
char Buffer[BUFFERSIZE];

// Global variables

jmp_buf exception;
unsigned int Freespace = 0;
char ReturnFlag = 0;
object *Freelist;
//extern uint8_t _end;

object *GlobalEnv;
object *GCStack = NULL;
char LastChar = 0;
char LastPrint = 0;
volatile char Escape = 0;

// Forward references
object *tee;

void error(char const *);
void error2 (object *symbol, char const * string);
object *eval (object *form, object *env);
char const * lookupbuiltin (symbol_t name);
void pchar (char c);
void pfl ();
void pint (int i);
void pln ();
void printobject(object *form);
void pstring (char const * s);
object *read();
extern "C" uint32_t syscall(uint32_t addr, uint32_t arg);

// Set up workspace

void initworkspace () {
  Freelist = NULL;
  for (int i=WORKSPACESIZE-1; i>=0; i--) {
    object *obj = &Workspace[i];
    car(obj) = NULL;
    cdr(obj) = Freelist;
    Freelist = obj;
    Freespace++;
  }
}

object *myalloc () {
  if (Freespace == 0) error("NO ROOM");
  object *temp = Freelist;
  Freelist = cdr(Freelist);
  Freespace--;
  return temp;
}

inline void myfree (object *obj) {
  car(obj) = NULL;
  cdr(obj) = Freelist;
  Freelist = obj;
  Freespace++;
}

// Make each type of object

object *cons (object *arg1, object *arg2) {
  object *ptr = myalloc();
  ptr->car = arg1;
  ptr->cdr = arg2;
  return ptr;
}

object *symbol (symbol_t name) {
  object *ptr = myalloc();
  ptr->type = SYMBOL;
  ptr->name = name;
  return ptr;
}

// Garbage collection

void markobject (object *obj) {
  MARK:
  if (obj == NULL) return;
  if (marked(obj)) return;

  object* arg = car(obj);
  unsigned int type = obj->type;
  mark(obj);
  
  if (type >= PAIR || type == ZERO) { // cons
    markobject(arg);
    obj = cdr(obj);
    goto MARK;
  }
}

void sweep () {
  Freelist = NULL;
  Freespace = 0;
  for (int i=WORKSPACESIZE-1; i>=0; i--) {
    object *obj = &Workspace[i];
    if (!marked(obj)) myfree(obj); else unmark(obj);
  }
}

void gc (object *form, object *env) {
  markobject(tee); 
  markobject(GlobalEnv);
  markobject(GCStack);
  markobject(form);
  markobject(env);
  sweep();
}

// Error handling

void error (char const * string) {
  pfl(); pstring("ERROR: ");
  pstring(string); pln();
  GCStack = NULL;
  longjmp(exception, 1);
}

void error2 (object *symbol, char const * string) {
  pfl(); pstring("ERROR: ");
  if (symbol == NULL) pstring("FUNCTION ");
  else { pchar('\''); printobject(symbol); pstring("' "); }
  pstring(string); pln();
  GCStack = NULL;
  longjmp(exception, 1);
}

// Helper functions

bool consp (object *x) {
  if (x == NULL) return false;
  unsigned int type = x->type;
  return type >= PAIR || type == ZERO;
}

bool atom (object *x) {
  if (x == NULL) return true;
  unsigned int type = x->type;
  return type < PAIR && type != ZERO;
}

bool listp (object *x) {
  if (x == NULL) return true;
  unsigned int type = x->type;
  return type >= PAIR || type == ZERO;
}

int toradix40 (char ch) {
  if (ch == 0) return 0;
  if (ch >= '0' && ch <= '9') return ch-'0'+30;
  if (ch >= 'A' && ch <= 'Z') return ch-'A'+1;
  //if (ch >= 'a' && ch <= 'z') return ch-'a'+1;
  return -1; // Invalid
}

int fromradix40 (int n) {
  if (n >= 1 && n <= 26) return 'A'+n-1;
  if (n >= 30 && n <= 39) return '0'+n-30;
  return 0;
}

int pack40 (char *buffer) {
  return (((toradix40(buffer[0]) * 40) + toradix40(buffer[1])) * 40 + toradix40(buffer[2]));
}

bool valid40 (char *buffer) {
 return (toradix40(buffer[0]) >= 0 && toradix40(buffer[1]) >= 0 && toradix40(buffer[2]) >= 0);
}

char const * name (object *obj) {
  if(!symbolp(obj)) error("ERROR IN NAME");
  symbol_t x = obj->name;
  if (x < ENDFUNCTIONS) return lookupbuiltin(x);
  Buffer[3] = '\0';
  for (int n=2; n>=0; n--) {
    Buffer[n] = fromradix40(x % 40);
    x = x / 40;
  }
  return Buffer;
}

int issymbol (object *obj, symbol_t n) {
  return symbolp(obj) && obj->name == n;
}

int eq (object *arg1, object *arg2) {
  int same_object = (arg1 == arg2);
  int same_symbol = (symbolp(arg1) && symbolp(arg2) && arg1->name == arg2->name);
  return (same_object || same_symbol);
}

object *progn (object *args, object *env) {
  if (args == NULL) return nil;
  object *more = cdr(args);
  while (more != NULL) {
  eval(car(args), env);
    args = more;
    more = cdr(args);
  }
  return car(args);
}

// Lookup variable in environment

object *value (symbol_t n, object *env) {
  while (env != NULL) {
    object *pair = car(env);
    if (pair != NULL && car(pair)->name == n) return pair;
    env = cdr(env);
  }
  return nil;
}

object *findvalue (object *var, object *env) {
  symbol_t varname = var->name;
  object *pair = value(varname, env);
  if (pair == NULL) pair = value(varname, GlobalEnv);
  if (pair == NULL) error2(var,"UNKNOWN VARIABLE");
  return pair;
}

object *findtwin (object *var, object *env) {
  while (env != NULL) {
    object *pair = car(env);
    if (pair != NULL && car(pair) == var) return pair;
    env = cdr(env);
  }
  return NULL;
}

void dropframe (int tc, object **env) {
  if (tc) {
    while (*env != NULL && car(*env) != NULL) {
      pop(*env);
    }
  } else {
    push(nil, *env);
  }
}

// Handling closures
  
object *closure (object *fname, object *function, object *args, object **env) {
  object *params = first(function);
  function = cdr(function);
  // Add arguments to environment
  while (params != NULL && args != NULL) {
    object *value;
    object *var = first(params);
    value = first(args);
    args = cdr(args);
    push(cons(var,value), *env);
    params = cdr(params);
  }
  if (params != NULL) error2(fname, "HAS TOO FEW PARAMETERS");
  if (args != NULL) error2(fname, "HAS TOO MANY PARAMETERS");
  // Do an implicit progn
  return progn(function, *env);
}

// Checked car and cdr

inline object *carx (object *arg) {
  if (!listp(arg)) error("CAN'T TAKE CAR");
  if (arg == nil) return nil;
  return car(arg);
}

inline object *cdrx (object *arg) {
  if (!listp(arg)) error("CAN'T TAKE CDR");
  if (arg == nil) return nil;
  return cdr(arg);
}

// Special forms

object *sp_quote (object *args, object *env) {
  (void) env;
  return first(args);
}

object *sp_defun (object *args, object *env) {
  (void) env;
  object *var = first(args);
  if (!symbolp(var)) error2(var, "IS NOT A SYMBOL");
  object *val = cons(symbol(LAMBDA), cdr(args));
  object *pair = value(var->name,GlobalEnv);
  if (pair != NULL) { cdr(pair) = val; return var; }
  push(cons(var, val), GlobalEnv);
  return var;
}

object *sp_defvar (object *args, object *env) {
  object *var = first(args);
  if (!symbolp(var)) error2(var, "IS NOT A SYMBOL");
  object *val = eval(second(args), env);
  object *pair = value(var->name,GlobalEnv);
  if (pair != NULL) { cdr(pair) = val; return var; }
  push(cons(var, val), GlobalEnv);
  return var;
}

object *sp_setq (object *args, object *env) {
  object *arg = eval(second(args), env);
  object *pair = findvalue(first(args), env);
  cdr(pair) = arg;
  return arg;
}

object *sp_if (object *args, object *env) {
  if (eval(first(args), env) != nil) return eval(second(args), env);
  return eval(third(args), env);
}

// Core functions

object *fn_not (object *args, object *env) {
  (void) env;
  return (first(args) == nil) ? tee : nil;
}

object *fn_cons (object *args, object *env) {
  (void) env;
  return cons(first(args),second(args));
}

object *fn_atom (object *args, object *env) {
  (void) env;
  return atom(first(args)) ? tee : nil;
}

object *fn_listp (object *args, object *env) {
  (void) env;
  return listp(first(args)) ? tee : nil;
}

object *fn_consp (object *args, object *env) {
  (void) env;
  return consp(first(args)) ? tee : nil;
}

object *fn_symbolp (object *args, object *env) {
  (void) env;
  return symbolp(first(args)) ? tee : nil;
}

object *fn_eq (object *args, object *env) {
  (void) env;
  return eq(first(args), second(args)) ? tee : nil;
}

// List functions

object *fn_car (object *args, object *env) {
  (void) env;
  return carx(first(args));
}

object *fn_cdr (object *args, object *env) {
  (void) env;
  return cdrx(first(args));
}

// System functions

object *fn_eval (object *args, object *env) {
  return eval(first(args), env);
}

object *fn_globals (object *args, object *env) {
  (void) args, (void) env;
  return GlobalEnv;
}

object *fn_locals (object *args, object *env) {
  (void) args;
  return env;
}

// Insert your own function definitions here

// Built-in procedure names

const char string0[] = "SYMBOLS";
const char string1[] = "NIL";
const char string2[] = "T";
const char string3[] = "LAMBDA";
const char string4[] = "SPECIAL_FORMS";
const char string5[] = "QUOTE";
const char string6[] = "DEFUN";
const char string7[] = "DEFVAR";
const char string8[] = "SETQ";
const char string9[] = "IF";
const char string10[] = "FUNCTIONS";
const char string11[] = "NOT";
const char string12[] = "NULL";
const char string13[] = "CONS";
const char string14[] = "ATOM";
const char string15[] = "LISTP";
const char string16[] = "CONSP";
const char string17[] = "SYMBOLP";
const char string18[] = "EQ";
const char string19[] = "CAR";
const char string20[] = "CDR";
const char string21[] = "EVAL";
const char string22[] = "GLOBALS";
const char string23[] = "LOCALS";

const tbl_entry_t lookup_table[] = {
  { string0, NULL, NIL, NIL },
  { string1, NULL, 0, 0 },
  { string2, NULL, 1, 0 },
  { string3, NULL, 0, 127 },
  { string4, NULL, NIL, NIL },
  { string5, sp_quote, 1, 1 },
  { string6, sp_defun, 0, 127 },
  { string7, sp_defvar, 2, 2 },
  { string8, sp_setq, 2, 2 },
  { string9, sp_if, 2, 3 },
  { string10, NULL, NIL, NIL },
  { string11, fn_not, 1, 1 },
  { string12, fn_not, 1, 1 },
  { string13, fn_cons, 2, 2 },
  { string14, fn_atom, 1, 1 },
  { string15, fn_listp, 1, 1 },
  { string16, fn_consp, 1, 1 },
  { string17, fn_symbolp, 1, 1 },
  { string18, fn_eq, 2, 2 },
  { string19, fn_car, 1, 1 },
  { string20, fn_cdr, 1, 1 },
  { string21, fn_eval, 1, 1 },
  { string22, fn_globals, 0, 0 },
  { string23, fn_locals, 0, 0 },
};

// Table lookup functions

bool streq (char const * a, char const * b) {
	for (;;) {
		if (*a != *b) {
			return false;
		}
		if (*a == '\0') {
			return true;
		}
		a++, b++;
	}
}

void strcpy (char* dest, char const * src) {
	for (;;) {
		*dest = *src;
		if (*src == '\0') {
			return;
		}
		dest++, src++;
	}
}

int builtin (char* n) {
  int entry = 0;
  while (entry < ENDFUNCTIONS) {
   if (streq(n, lookup_table[entry].string))
      return entry;
    entry++;
  }
  return ENDFUNCTIONS;
}

fn_ptr_type lookupfn (symbol_t name) {
  return lookup_table[name].fptr;
}

int lookupmin (symbol_t name) {
  return lookup_table[name].min;
}

int lookupmax (symbol_t name) {
  return lookup_table[name].max;
}

char const * lookupbuiltin (symbol_t name) {
  strcpy(Buffer, lookup_table[name].string);
  return Buffer;
}

// Main evaluator

object *eval (object *form, object *env) {
  // Enough space?
  if (Freespace < 20) gc(form, env);
  // Escape
  if (Escape) { Escape = 0; error("ESCAPE!");}
  
  if (form == NULL) return nil;

  if (symbolp(form)) {
    symbol_t name = form->name;
    if (name == NIL) return nil;
    object *pair = value(name, env);
    if (pair != NULL) return cdr(pair);
    pair = value(name, GlobalEnv);
    if (pair != NULL) return cdr(pair);
    else if (name <= ENDFUNCTIONS) return form;
    error2(form, "UNDEFINED");
  }
  
  // It's a list
  object *function = car(form);
  object *args = cdr(form);

  // List starts with a symbol?
  if (symbolp(function)) {
    symbol_t name = function->name;

    if (name == LAMBDA) {
      if (env == NULL) return form;
      error("CLOSURES NOT SUPPORTED");
    }
    
    if ((name > SPECIAL_FORMS) && (name < FUNCTIONS)) {
      return ((fn_ptr_type)lookupfn(name))(args, env);
    }
  }
        
  // Evaluate the parameters - result in head
  object *fname = car(form);
  object *head = cons(eval(car(form), env), NULL);
  push(head, GCStack); // Don't GC the result list
  object *tail = head;
  form = cdr(form);
  int nargs = 0;

  while (form != NULL) {
    object *obj = cons(eval(car(form),env),NULL);
    cdr(tail) = obj;
    tail = obj;
    form = cdr(form);
    nargs++;
  }
    
  function = car(head);
  args = cdr(head);
 
  if (symbolp(function)) {
    symbol_t name = function->name;
    if (name >= ENDFUNCTIONS) error2(fname, "IS NOT VALID HERE");
    if (nargs<lookupmin(name)) error2(fname, "HAS TOO FEW ARGUMENTS");
    if (nargs>lookupmax(name)) error2(fname, "HAS TOO MANY ARGUMENTS");
    object *result = ((fn_ptr_type)lookupfn(name))(args, env);
    pop(GCStack);
    return result;
  }
      
  if (listp(function) && issymbol(car(function), LAMBDA)) {
    dropframe(0, &env);
    form = closure(fname, cdr(function), args, &env);
    pop(GCStack);
    return eval(form, env);
  } 
  
  error2(fname, "IS AN ILLEGAL FUNCTION"); return nil;
}

// Print functions

void cout(char c) {
	const uint32_t couta = 0xfded;
	syscall(couta, (uint32_t)c);
}

char rdkey() {
	const uint32_t rdkeya = 0xfd0c;
	return (char)syscall(rdkeya, 0);
}

void pchar (char c) {
  LastPrint = c;
  cout(0x80 | c);
}

void pstring (char const * s) {
  while (*s) pchar(*s++);
}

int abs(int i) {
	if (i < 0) {
		return -i;
	}
	return i;
}

//void phex(uint8_t b) {
//	uint8_t n = b & 0xf;
//	pchar(n + (n < 10 ? '0' : 'A'));
//}
//
//void pbyte(uint8_t b) {
//	phex(b);
//	phex(b >> 4);
//}

void pint (int n) {
//	unsigned int u = n;
//	pchar('$');
//	pbyte(u >> 24);
//	pbyte(u >> 16);
//	pbyte(u >> 8);
//	pbyte(u);

  int lead = 0;
  if (n<0) pchar('-');
  for (int d=10000; d>0; d=d/10) {
    int j = n/d;
    if (j!=0 || lead || d==1) { pchar(abs(j)+'0'); lead=1;}
    n = n - j*d;
  }
}

void pln () {
  pchar('\r');
}

void pfl () {
  if (LastPrint != '\r') pchar('\r');
}

void printobject(object *form){
  if (form == NULL) pstring("NIL");
  else if (listp(form)) {
    pchar('(');
    printobject(car(form));
    form = cdr(form);
    while (form != NULL && listp(form)) {
      pchar(' ');
      printobject(car(form));
      form = cdr(form);
    }
    if (form != NULL) {
      pstring(" . ");
      printobject(form);
    }
    pchar(')');
  } else if (symbolp(form)) {
    pstring(name(form));
  } else
    error("ERROR IN PRINT.");
}

int gchar () {
  if (LastChar) { 
    char temp = LastChar;
    LastChar = 0;
    return temp;
  }

  char temp = rdkey();
  if (temp != '\r') pchar(temp);
  return temp & 0x7f;
}

bool isspace(char c) {
	return c == ' ' || c == '\t';
}

object *nextitem() {
  int ch = gchar();
  while(isspace(ch)) ch = gchar();

  if (ch == ';') {
    while(ch != '(') ch = gchar();
    ch = '(';
  }
  if (ch == '\r') ch = gchar();
  //if (ch == EOF) exit(0);

  if (ch == ')') return (object *)KET;
  if (ch == '(') return (object *)BRA;
  if (ch == '\'') return (object *)QUO;
  if (ch == '.') return (object *)DOT;
  
  // Parse variable
  int index = 0;
  Buffer[2] = '\0'; // In case variable is one letter

  while(!isspace(ch) && ch != ')' && ch != '(' && index < BUFFERSIZE-1) {
    Buffer[index++] = ch;
    ch = gchar();
  }

  Buffer[index] = '\0';
  if (ch == ')') LastChar = ')';
  if (ch == '(') LastChar = '(';

  int x = builtin(Buffer);
  if (x == NIL) return nil;
  if (x < ENDFUNCTIONS) return symbol(x);
  else if (index < 4 && valid40(Buffer)) return symbol(pack40(Buffer));
  error("ILLEGAL SYMBOL");
  return nil;
}

object *readrest() {
  object *item = nextitem();

  if(item == (object *)KET) return NULL;
  
  if(item == (object *)DOT) {
    object *arg1 = read();
    if (readrest() != NULL) error("MALFORMED LIST");
    return arg1;
  }

  if(item == (object *)QUO) {
    object *arg1 = read();
    return cons(cons(symbol(QUOTE), cons(arg1, NULL)), readrest());
  }
   
  if(item == (object *)BRA) item = readrest(); 
  return cons(item, readrest());
}

object *read() {
  object *item = nextitem();
  if (item == (object *)BRA) return readrest();
  if (item == (object *)DOT) return read();
  if (item == (object *)QUO) return cons(symbol(QUOTE), cons(read(), NULL)); 
  return item;
}

// Setup

void initenv() {
  GlobalEnv = NULL;
  tee = symbol(TEE);
}

static uint8_t volatile * altchr = (uint8_t volatile *)0xc00f;

void setup() {
  const uint32_t clrscr = 0xfc9c;
  syscall(clrscr, 0);
  initworkspace();
  initenv();
  pstring("ULISP ZERO 1.1"); pln();
}

// Read/Evaluate/Print loop

void repl(object *env) {
  for (;;) {
    gc(NULL, env);
    pint(Freespace);
    pstring("> ");
    object *line = read();
    if (line == (object *)KET) error("UNMATCHED RIGHT BRACKET");
    push(line, GCStack);
    pfl();
    line = eval(line, env);
    pfl();
    printobject(line);
    pop(GCStack);
    pfl();
    pln();
  }
}

int main() {
  setup();
  setjmp(exception);
  repl(NULL);
}
