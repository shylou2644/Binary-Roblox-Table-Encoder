Easy to use binary encoder. Supports only native lua types: number, string, table

Uses buffers for effeciency. buffers can be saved directly to a datastore without converting to a string, avoiding UTF8 errors when using :SaveAsync()
