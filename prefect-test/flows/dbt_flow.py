from prefect import flow
from prefect_dbt.cli.commands import DbtCoreOperation, trigger_dbt_cli_command

DBT_PROJECT_DIR = "/home/kohada/dbt-core-service-calls"


@flow
def trigger_dbt_flow() -> str:
    """
    list of commands allowed?
    """
    result = DbtCoreOperation(
        commands=["pwd", "dbt debug", "dbt test"],
        project_dir=DBT_PROJECT_DIR,
        profiles_dir=DBT_PROJECT_DIR,
    ).run()
    return result


trigger_dbt_flow()


@flow
def trigger_dbt_cli_command_flow():
    """
    single command only
    """
    result = trigger_dbt_cli_command(
        command="dbt debug",
        profiles_dir=DBT_PROJECT_DIR,
        project_dir=DBT_PROJECT_DIR,
    )
    return result


# trigger_dbt_cli_command_flow()
