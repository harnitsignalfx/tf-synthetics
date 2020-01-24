import json
import requests
import signalfx_lambda
import time


# Our registered Lambda handler entrypoint (example.request_handler) with the
# SignalFx Lambda wrapper
@signalfx_lambda.emits_metrics
def request_handler(event, context):
        url = ''
        try:
                with open('urlfile') as f:
                        url = f.readline().strip('\n')
        except:
          signalfx_lambda.send_gauge('responseTime', elapsedTime, {'Status':'URL not specified','Url':url})                      
          return
        elapsedTime = 0
        try:
                rqst = requests.get(url)
                elapsedTime = rqst.elapsed.total_seconds()*1000
                StatusCode = rqst.status_code
                print('Url->',url,'StatusCode->',StatusCode,'elapsedTime->',elapsedTime)
                signalfx_lambda.send_gauge('responseTime', elapsedTime, {'Status':str(StatusCode),'Url':url})
        except requests.exceptions.Timeout:
                signalfx_lambda.send_gauge('responseTime', 0, {'Status':'Timeout Error','Url':url})
        except requests.exceptions.TooManyRedirects:
                signalfx_lambda.send_gauge('responseTime', 0, {'Status':'Too many redirects Error','Url':url})
        except requests.exceptions.RequestException:
                signalfx_lambda.send_gauge('responseTime', 0, {'Status':'Request Exception Error','Url':url})