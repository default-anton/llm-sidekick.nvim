from auto_context.code_chunker import chunk_code

sample_path = "sample.rb"
with open(sample_path, 'r') as f:
    sample_code = f.read()

chunks = chunk_code(sample_code, sample_path)
for chunk in chunks:
    print(chunk.content)
    print("-" * 80)
