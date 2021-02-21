#!/bin/bash

node generate-pageviews.js|ccloud kafka topic produce pageviews
