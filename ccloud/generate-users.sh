#!/bin/bash

node generate-users.js|ccloud kafka topic produce users
