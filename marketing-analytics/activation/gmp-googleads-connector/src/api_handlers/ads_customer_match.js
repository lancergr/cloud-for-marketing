// Copyright 2019 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * @fileoverview Tentacles API handler for Campaign Manager Conversions
 * uploading (DfaReport API).
 */

'use strict';

const {
  utils: {apiSpeedControl, getProperValue},
} = require('nodejs-common');

/** API name in the incoming file name. */
exports.name = 'AC';

/** Data for this API will be transferred through GCS by default. */
exports.defaultOnGcs = false;

let GoogleAdsConfig;

exports.GoogleAdsConfig = GoogleAdsConfig;

exports.sendData = (records, messageId, config) => {
  return true;
};
