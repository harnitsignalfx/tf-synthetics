resource "local_file" "urlfile" {
    content     = "https://www.yahoo.com"
    filename = "${path.module}/python-syn/urlfile"
}

provider "signalfx" {
    auth_token = "YOUR_TOKEN"
    api_url = "https://api.signalfx.com"
}

data "archive_file" "init" {
  type        = "zip"
  source_dir = "${path.module}/python-syn"
  output_path = "${path.module}/output-zip/python-syn.zip"

  depends_on = [
    local_file.urlfile
  ]
}

# Specify the provider and access details
provider "aws" {
	profile = "default"
	region = "us-east-1"
}

data "aws_iam_policy_document" "policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = format("%s_%s","iam_for_lambda",replace(replace(local_file.urlfile.content,"https://",""),".","_"))
  assume_role_policy = data.aws_iam_policy_document.policy.json
}

resource "aws_lambda_function" "syn_lambda" {
  function_name = format("%s_%s","syn_check_lambda",replace(replace(local_file.urlfile.content,"https://",""),".","_"))

  filename         = data.archive_file.init.output_path
  source_code_hash = data.archive_file.init.output_base64sha256

  role    = aws_iam_role.iam_for_lambda.arn
  handler = "pythonLambda.request_handler"
  runtime = "python3.6"
  timeout = 10

  environment {
    variables = {
      SIGNALFX_ACCESS_TOKEN = "YOUR_TOKEN"
      SIGNALFX_ENDPOINT_URL = "https://ingest.signalfx.com"
    }
  }
}

resource "aws_cloudwatch_event_rule" "every_one_minute" {
    name = format("%s_%s","every-minute",replace(replace(local_file.urlfile.content,"https://",""),".","_"))
    description = "Fires every minute"
    schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "syn_lambda_every_one_minute" {
    rule = aws_cloudwatch_event_rule.every_one_minute.name
    target_id = "syn_lambda"
    arn = aws_lambda_function.syn_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_syn_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.syn_lambda.function_name
    principal = "events.amazonaws.com"
    source_arn = aws_cloudwatch_event_rule.every_one_minute.arn
}





resource "signalfx_detector" "url_stopped_reporting" {
    name = "Url is not responding"

    program_text = <<-EOF
        from signalfx.detectors.not_reporting import not_reporting
        not_reporting.detector(data('responseTime'),'Url','2m').publish('Url not reporting')
    EOF
    rule {
        description = "URL not responding for 2m"
        severity = "Critical"
        detect_label = "Url not reporting"
        notifications = ["VictorOps,EPEGl7EAYAA,synteam"]
    }

}

resource "signalfx_dashboard_group" "dashboardgroup0" {
    name = "Synthetics"
    description = "Status of public facing websites"
}

resource "signalfx_time_chart" "mychart0" {
    name = "Response Time (ms)"

    program_text = <<-EOF
        A = data("responseTime").publish(label="Response Time")
        B = alerts(detector_id="${signalfx_detector.url_stopped_reporting.id}").publish(label='B')
        EOF

    plot_type = "LineChart"
    show_data_markers = true

    legend_options_fields {
      property = "Url"
      enabled = true
    }
    
    viz_options {
        label = "Response Time"
        axis = "left"
        color = "orange"
    }
}

resource "signalfx_list_chart" "mychart1" {
    name = "Response Time by Status and Url"

    program_text = <<-EOF
        A = data('responseTime').sum(by=['Status', 'Url']).publish(label="Response Time")
        EOF

    legend_options_fields {
      property = "metric"
      enabled  = false
    }

    legend_options_fields {
      property = "Plot Name"
      enabled = false
    }
    legend_options_fields {
      property = "Status"
      enabled = true
    }   
    legend_options_fields {
      property = "Url"
      enabled = true
    }
    
    
}


resource "signalfx_dashboard" "mydashboard0" {
    name = "Response Time"
    dashboard_group = signalfx_dashboard_group.dashboardgroup0.id

    time_range = "-30m"

    chart {
        chart_id = signalfx_time_chart.mychart0.id
        row = 0
        column = 0
        width = 6
        height = 2
    }
    chart {
        chart_id = signalfx_list_chart.mychart1.id
        row = 0
        column = 6
        width = 6
        height = 2
    }
}



resource "signalfx_list_chart" "mychart2" {
    name = "Monthly Compute charges"

    program_text = <<-EOF
        A = data('responseTime').count(by=['Url']).publish(label='A', enable=False)
        B = ((A*21600*128/1024)).publish(label='B', enable=False)
        C = B*200
        D = ((C-400000)*0.00001667).above(0, inclusive=True, clamp=True).publish(label='Monthly compute charges')
        EOF

    legend_options_fields {
      property = "Url"
      enabled = true
    }
    legend_options_fields {
      property = "metric(sf_metric)"
      enabled  = false
    }
    legend_options_fields {
      property = "Plot Name"
      enabled  = false
    }
    
    sort_by = "-value"
}

resource "signalfx_list_chart" "mychart3" {
    name = "Monthly Request charges"

    program_text = <<-EOF
        A = data('responseTime').count(by=['Url']).publish(label='A', enable=False)
        B = (A*21600).publish(label='B', enable=False)
        C = B*200
        D = (((C-1000000)/1000000)*0.2).above(0, inclusive=True, clamp=True).publish(label='Monthly request charges')
        EOF

    legend_options_fields {
      property = "Url"
      enabled = true
    }
    legend_options_fields {
      property = "metric(sf_metric)"
      enabled  = false
    }
    legend_options_fields {
      property = "Plot Name"
      enabled  = false
    }
    
    sort_by = "-value"
    
}

resource "signalfx_list_chart" "mychart4" {
    name = "Total Monthly Charges"

    program_text = <<-EOF
        A = data('responseTime').count(by=['Url']).publish(label='A', enable=False)
        B = ((A*21600*128/1024)).publish(label='B', enable=False)
        C = B*200
        D = ((C-400000)*0.00001667).above(0, inclusive=True, clamp=True).publish(label='Monthly compute charges',enable=False)
        E = (A*21600).publish(label='B', enable=False)
        F = E*200
        G = (((F-1000000)/1000000)*0.2).above(0, inclusive=True, clamp=True).publish(label='Monthly request charges',enable=False)
        H = (D+G).publish(label='Total Monthly Charges')
        EOF

 
    legend_options_fields {
      property = "Url"
      enabled = true
    }
    legend_options_fields {
      property = "metric(sf_metric)"
      enabled  = false
    }
    legend_options_fields {
      property = "Plot Name"
      enabled  = false
    }

    sort_by = "-value"
    
    
}

resource "signalfx_dashboard" "mydashboard1" {
    name = "Monthly Charges"
    dashboard_group = signalfx_dashboard_group.dashboardgroup0.id

    time_range = "-30m"

    chart {
        chart_id = signalfx_list_chart.mychart2.id
        row = 0
        column = 0
        width = 3
        height = 2
    }
    chart {
        chart_id = signalfx_list_chart.mychart3.id
        row = 0
        column = 3
        width = 3
        height = 2
    }
    chart {
        chart_id = signalfx_list_chart.mychart4.id
        row = 0
        column = 6
        width = 6
        height = 2
    }
}