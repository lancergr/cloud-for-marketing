import base64
import json
from googleads import adwords
from google.cloud import firestore

def request_api(event, context):
  api_handlers = {'AC': send_data_customer_match}

  pubsub_message = base64.b64decode(event['data']).decode('utf-8')
  config = event['attributes']

  db = firestore.Client()

  api_config_ref = db.collection(u'tentacles').document(
    u'ApiConfig').collection(config['api']).document(config['config'])
  api_config = api_config_ref.get().to_dict()

  api_handler = api_handlers.get(config['api'], api_not_supported)
  return api_handler(pubsub_message, context.event_id, api_config)


def get_ads_api_client(config):
  yaml_string = build_client_string(config['clientCustomerId'],
                                    config['developerToken'],
                                    config['clientId'], config['clientSecret'],
                                    config['refreshToken'])
  ads_api_client = adwords.AdWordsClient.LoadFromString(yaml_string)
  return ads_api_client


def build_client_string(client_customer_id, developer_token, client_id,
    client_secret, google_ads_refresh_token):
  string = "adwords:\n"
  string += '  client_customer_id: ' + client_customer_id + '\n'
  string += '  developer_token: ' + developer_token + '\n'
  string += '  client_id: ' + client_id + '\n'
  string += '  client_secret: ' + client_secret + '\n'
  string += '  refresh_token: ' + google_ads_refresh_token
  return string


def send_data_customer_match(records, messageId, config):
  hashed_emails = records.splitlines()
  print('Processing %d emails' % (len(hashed_emails)) )

  client = get_ads_api_client(config)
  user_list_service = client.GetService('AdwordsUserListService', 'v201809')

  list_name = config['userListName']

  # Check if the list already exists
  selector = {
      'fields': ['Name', 'Id'],
      'predicates': [{
          'field': 'Name',
          'operator': 'EQUALS',
          'values': list_name
      }],
  }

  result = user_list_service.get(selector)
  if result['entries']:
    print('The user list %s is already created and its info was retrieved.',
          list_name)
    user_list_id = result['entries'][0]['id']
  else:
    print('The user list %s will be created.', list_name)
    user_list = {
        'xsi_type': 'CrmBasedUserList',
        'name': list_name,
        'description': 'This is a list of users uploaded from Tentacles',
        # CRM-based user lists can use a membershipLifeSpan of 10000 to indicate
        # unlimited; otherwise normal values apply.
        'membershipLifeSpan': 10000,
        'uploadKeyType': 'CONTACT_INFO'
    }

    # Create an operation to add the user list.
    operations = [{'operator': 'ADD', 'operand': user_list}]
    result = user_list_service.mutate(operations)
    user_list_id = result['value'][0]['id']

  members = [json.loads(email) for email in hashed_emails]

  mutate_members_operation = {
      'operand': {
          'userListId': user_list_id,
          'membersList': members
      },
      'operator': 'ADD'
  }

  response = user_list_service.mutateMembers([mutate_members_operation])

  if 'userLists' in response:
    for user_list in response['userLists']:
      print('User list with name "%s" and ID "%d" was added.'
            % (user_list['name'], user_list['id']))

def api_not_supported(records, messageId, config):
  print("Api not supported" + messageId)
