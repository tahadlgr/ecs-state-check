import json
from botocore.vendored import requests
import boto3
from pprint import pprint
import os
from typing import Any, Dict, List
import urllib3


def lambda_handler(event, context):
    try:
        event_as_string = json.dumps(event)
        formatted_event = {
            "blocks": [
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"{event_as_string}"},
                },
                {"type": "divider"},
            ]
        }

        http = urllib3.PoolManager()
        r2 = http.request(
            "POST",
            "https://hooks.slack.com/services/complete-with-your-webhook-url",
            body=json.dumps(formatted_event),
            headers={"Content-Type": "event/json"},
        )
        print(r2.read())

    except Exception as e:
        raise e

    main_account_id = boto3.client("sts").get_caller_identity().get("Account").strip()
    account_id = event["account"]
    account_alias = (
        boto3.client("organizations")
        .describe_account(AccountId=account_id)
        .get("Account")
        .get("Name")
    )

    account_alias_formatter = account_alias.split("-")
    if account_alias_formatter[0] == "lifemote":
        del account_alias_formatter[0]
        account_alias = "-".join(account_alias_formatter)

    if main_account_id == account_id:
        ecs = boto3.client("ecs")
    else:
        boto_sts = boto3.client("sts")

        stsresponse = boto_sts.assume_role(
            RoleArn=f"arn:aws:iam::{account_id}:role/ecs-api-access-cross-account-role",
            RoleSessionName="Newsession",
        )

        newsession_id = stsresponse["Credentials"]["AccessKeyId"]
        newsession_key = stsresponse["Credentials"]["SecretAccessKey"]
        newsession_token = stsresponse["Credentials"]["SessionToken"]

        ecs = boto3.client(
            "ecs",
            region_name="eu-central-1",
            aws_access_key_id=newsession_id,
            aws_secret_access_key=newsession_key,
            aws_session_token=newsession_token,
        )

    cluster_name = event["detail"]["clusterArn"].split("/")[1]
    # containerLastStatus = event["detail"]["containers"][0]["lastStatus"]
    # desiredStatus = event["detail"]["desiredStatus"]
    task_last_status = event["detail"]["lastStatus"]
    task_arn = event["detail"]["taskArn"]
    service_info = event["detail"]["group"].split(":")[1]

    service_info_formatter = service_info.split("-")
    if service_info_formatter[-1] == "service":
        del service_info_formatter[-1]
        service_info = "-".join(service_info_formatter)

    response = ecs.describe_tasks(cluster=cluster_name, tasks=list(task_arn.split()))[
        "tasks"
    ]
    task_health_status = response[0]["healthStatus"]
    task_desired_status = response[0]["desiredStatus"]

    print(
        "environment: %s service: %s taskArn: %s taskLastStatus: %s taskHealthStatus: %s taskDesiredStatus: %s"
        % (
            account_alias,
            service_info,
            task_arn,
            task_last_status,
            task_health_status,
            task_desired_status,
        )
    )

    container_exit_code = response[0]["containers"][0].get("exitCode", "NotFound")
    container_reason = response[0]["containers"][0].get("reason", "NotFound")
    task_started_at = response[0].get("startedAt", "NotFound")

    if (
        (task_last_status == "STOPPING" and task_health_status == "UNHEALTHY")
        or (
            (task_last_status == "STOPPING" or task_last_status == "STOPPED")
            and (
                container_exit_code != 0
                and container_exit_code != 143
                and container_exit_code != "NotFound"
            )
        )
        or (task_last_status == "STOPPED" and task_desired_status != "STOPPED")
    ):
        stopping_at = event["detail"].get("stoppingAt", "NotFound")
        stopped_reason = event["detail"].get("stoppedReason", "NotFound")
        stop_code = event["detail"].get("stopCode", "NotFound")

        ### This if case can be removed, if all healthchecks and container exits are appropriately designed.
        stopped_reason_as_list = stopped_reason.split(" ")
        if "(deployment" not in stopped_reason_as_list and (
            account_alias != "test" and account_alias != "staging"
        ):
            try:
                print(event)
                send_slack_notification(
                    service_info=service_info,
                    account_alias=account_alias,
                    stopping_at=stopping_at,
                    stopped_reason=stopped_reason,
                    stop_code=stop_code,
                    container_exit_code=container_exit_code,
                    container_reason=container_reason,
                    task_started_at=task_started_at,
                    event=event,
                )
            except Exception as e:
                raise e
    return


def send_slack_notification(
    service_info,
    account_alias,
    stopping_at,
    stopped_reason,
    stop_code,
    container_exit_code,
    container_reason,
    task_started_at,
    event,
):
    data = {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{account_alias} -> {service_info}",
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"Stop reason: *{stopped_reason}* \nStop code: *{stop_code}* \nExit code and reason: {container_exit_code}   {container_reason} \nStarted at: {task_started_at} \nStopped at: {stopping_at}",
                },
            },
        ]
    }

    # requests.post(slack_webhook, json=data)
    http = urllib3.PoolManager()
    r = http.request(
        "POST",
        os.getenv("SLACK_WEBHOOK_URL"),
        body=json.dumps(data),
        headers={"Content-Type": "application/json"},
        retries=False,
    )

    print(r.read())
