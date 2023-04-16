from prefect.blocks.system import Secret

secret_block = Secret(value="helllooooo")
secret_block.save(
    name="big-secret",  # no underscore
    overwrite=True,
)
