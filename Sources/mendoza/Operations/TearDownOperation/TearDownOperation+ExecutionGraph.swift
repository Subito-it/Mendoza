//
//  TearDownOperation+ExecutionGraph.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/09/21.
//

import Foundation

enum ExecutionGraph {
    static let template = """
    <html>
    <meta charset="UTF-8">
    <head>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-weight: normal;
                color: rgb(30, 30, 30);
                font-size: 80%;
                margin: 10px;
            }

            #canvas {
              position: relative;
              margin-left: 20px;
            }

            #position {
              position: fixed;
              width: 100%;
              margin-left: -10px;
              padding: 5px;
              padding-left: 12px;
              bottom: 0px;
              background-color: rgb(240, 240, 240);
              border-style: solid;
              border-width: 1px;
              border-color: rgb(220, 220, 220);
              color: rgb(120, 120, 120);
            }

            #canvas div {
              position: absolute;
              color: rgb(50, 50, 50);
              border-radius: 5px;
            }

            #canvas .separator {
              background-color: rgb(240,240,240);
              left: 0px;
              height: 1px;
              width: 100%;
            }

            #canvas .bar-color {
              background-color: rgb(47,124,246) !important;
            }

            #canvas .success-test {
              background-color: rgb(20,149,61);
            }

            #canvas .fail-test {
              background-color: rgb(223,26,33);
            }

            #canvas .operation {
              background-color: rgb(245, 245, 245);
              border-color: rgb(220,220,220);
              border-width: 1px;
            }

            #execution-details {
              font-size: 100%;
            }

            #detail-separator {
              background-color: rgb(200,200,200);
              left: 0px;
              height: 1px;
            }
        </style>
    </head>
    <body>

    <h1>Execution graph</h1>

    <div id="canvas"></div>
    <div id="position"></div>

    <div id="detail-separator"></div>

    <div id="execution-details">
      <h1>Execution details</h1>
      <div id="slowTestStartIntervals"></div>
    </div>

    <div id="footer" style="height:40px;"></div>

    <script type="text/javascript">
      const rawData = String.raw`
    $$TEST_DETAIL_JSON
      `;

      const pixelsPerSecond = 6.0;
      const ipHeight = 15.0;
      const ipSeparator = 5.0;
      const testHeight = 15.0;
      const testSeparator = 8.0;
      const operationDivHeight = 15.0;
      const operationDivSeparator = 12.0;

      function formatTime(delta) {
        if (delta < 1.0) {
          return `${Math.trunc(delta * 1000)}ms`
        } else if (delta > 60.0) {
          const minutes = Math.floor(delta / 60.0);
          const seconds = delta - minutes * 60;

          return `${minutes}m${Math.trunc(seconds)}s`
        } else {
          return `${delta.toFixed(1)}s`
        }
      }

      document.onmousemove = function(e) {
        const positionDiv = document.getElementById("position");
        const leftMargin = parseInt(window.getComputedStyle(document.getElementById("canvas")).getPropertyValue("margin-left"), 10) + parseInt(window.getComputedStyle(document.body).getPropertyValue("margin-left"), 10);

        var currentPosition = Math.trunc((window.scrollX + e.clientX - leftMargin) / pixelsPerSecond);
        currentPosition = Math.max(0, currentPosition);
        positionDiv.innerHTML = `Curson position: ${currentPosition}s`;
      }

      const data = JSON.parse(rawData);
      var tests = data.passedTests.concat(data.failedTests, data.retriedTests);
      tests = tests.sort((a, b) => (a.startInterval > b.startInterval) ? 1 : -1)

      const nodes = {};
      for (let index in tests) {
        const destinations = nodes[tests[index].node] || [];
        destinations.push(tests[index].runnerName);
        nodes[tests[index].node] = [...new Set(destinations)].sort();;
      }

      var minStartInterval = Number.MAX_SAFE_INTEGER;
      for (let key in data.operationStartInterval) {
        if (data.operationStartInterval[key] > 0.0) {
          minStartInterval = Math.min(minStartInterval, data.operationStartInterval[key]);
        }
      }

      var maxEndInterval = 0.0;
      for (let key in data.operationEndInterval) {
        if (data.operationEndInterval[key] > 0.0) {
          maxEndInterval = Math.max(maxEndInterval, data.operationEndInterval[key]);
        }
      }

      var operations = [];
      for (let key in data.operationStartInterval) {
        if (key in data.operationEndInterval) {
          if (data.operationStartInterval[key] > 0.0 && data.operationEndInterval[key] > 0.0) {
            operations.push({name: key, startInterval: data.operationStartInterval[key] - minStartInterval, endInterval: data.operationEndInterval[key] - minStartInterval});
          }

          for (let poolKey in data.operationPoolStartInterval[key]) {
            data.operationPoolStartInterval[key][poolKey] -= minStartInterval;
          }
          for (let poolKey in data.operationPoolEndInterval[key]) {
            data.operationPoolEndInterval[key][poolKey] -= minStartInterval;
          }
        }
      }
      operations = operations.sort((a, b) => (a.startInterval > b.startInterval) ? 1 : -1);

      for (let index in tests) {
        tests[index].startInterval -= minStartInterval;
        tests[index].endInterval -= minStartInterval;
      }

      const canvas = document.getElementById("canvas");

      let testOperationDuration = 0;
      let testsLaunchInterval = [];

      var currentTop = 0.0;
      for (let index in operations) {
        const operation = operations[index];

        var separatorDiv = document.createElement("div");
        separatorDiv.classList.add("separator");
        separatorDiv.style.top = `${currentTop}px`;
        canvas.appendChild(separatorDiv);
        currentTop += operationDivSeparator;

        const operationTitleDivFontSize = 20;
        var operationTitleDiv = document.createElement("div");
        operationTitleDiv.style.top = `${currentTop}px`;
        operationTitleDiv.style.left = `${operation.startInterval * pixelsPerSecond}px`;
        operationTitleDiv.innerHTML = `${operation.name} - ${formatTime(operation.endInterval - operation.startInterval)}`;
        canvas.appendChild(operationTitleDiv);
        currentTop += operationTitleDivFontSize;

        var currentOperationDivHeight = operationDivHeight;
        const width = Math.max(0.5 * pixelsPerSecond, (operation.endInterval - operation.startInterval) * pixelsPerSecond);

        var operationDiv = document.createElement("div");
        operationDiv.classList.add("operation")
        operationDiv.style.top = `${currentTop}px`;
        operationDiv.style.left = `${operation.startInterval * pixelsPerSecond}px`;
        operationDiv.style.width = `${width}px`;

        operationDiv.style.borderStyle = "solid";

        canvas.appendChild(operationDiv);

        const startingTop = currentTop;

        if (operation.name == "TestRunnerOperation") {
          testOperationDuration = operation.endInterval - operation.startInterval;

          currentTop += testSeparator;

          const sortedNodes = Object.keys(nodes).sort();
          for (let ip of sortedNodes) {
            const runnerNames = nodes[ip];

            for (let runnerName of runnerNames) {
              var previousTest = null;
              for (let test of tests) { // tests are sorted by startInterval
                if (test.node == ip && test.runnerName == runnerName) {
                  const startInterval = test.startInterval;
                  const endInterval = test.endInterval;

                  var testDiv = document.createElement("div");
                  testDiv.classList.add(test.status == 0 ? "success-test" : "fail-test");
                  testDiv.setAttribute("title", `${test.suite}/${test.name}\n${ip}\n${runnerName}\n${formatTime(endInterval - startInterval)}`);
                  testDiv.style.top = `${currentTop}px`;
                  testDiv.style.left = `${startInterval * pixelsPerSecond}px`;
                  testDiv.style.width = `${(endInterval - startInterval) * pixelsPerSecond}px`;
                  testDiv.style.height = `${testHeight}px`;

                  canvas.appendChild(testDiv);

                  if (previousTest) {
                    testsLaunchInterval.push({"previousTest": previousTest, "test": test, "deltaInterval": test.startInterval - previousTest.endInterval });
                  }
                  previousTest = test;
                }
              }

              currentTop += testHeight + testSeparator;

              var separatorDiv = document.createElement("div");
              separatorDiv.classList.add("separator");
              separatorDiv.style.top = `${currentTop}px`;
              separatorDiv.style.left = `${operation.startInterval * pixelsPerSecond}px`;
              separatorDiv.style.width = `${width}px`;

              separatorDiv.style.backgroundColor = "rgb(220,220,220)";

              const isLastRunner = runnerNames.slice(-1)[0] == runnerName;
              const isNode = sortedNodes.slice(-1)[0] == ip;

              if (!(isLastRunner && isNode)) {
                canvas.appendChild(separatorDiv);
                currentTop += testSeparator;
              } else {
                currentTop -= testHeight;
              }
            }
          }

          currentTop += operationDivSeparator;
        } else {
          if (Object.keys(data.operationPoolStartInterval[operation.name]).length > 0) {
            currentTop += ipSeparator;

            const sortedNodes = Object.keys(data.operationPoolStartInterval[operation.name]).sort();
            for (let ip of sortedNodes) {
              const startInterval = data.operationPoolStartInterval[operation.name][ip];
              const endInterval = data.operationPoolEndInterval[operation.name][ip];

              var poolDiv = document.createElement("div");
              poolDiv.classList.add("bar-color");
              poolDiv.setAttribute("title", `${ip} - ${formatTime(endInterval - startInterval)}`);
              poolDiv.style.top = `${currentTop}px`;
              poolDiv.style.left = `${startInterval * pixelsPerSecond}px`;
              poolDiv.style.width = `${(endInterval - startInterval) * pixelsPerSecond}px`;
              poolDiv.style.height = `${ipHeight}px`;

              canvas.appendChild(poolDiv);

              currentTop += ipHeight + ipSeparator;
            }

            currentTop += operationDivSeparator - ipHeight;
          } else {
            operationDiv.classList.add("bar-color");
            operationDiv.style.borderStyle = "none";
            currentTop += operationDivHeight;
          }
        }
        currentOperationDivHeight = currentTop - startingTop;
        currentTop = startingTop + currentOperationDivHeight + operationDivSeparator;

        operationDiv.style.height = `${currentOperationDivHeight}px`;
      }

      const lastLeft = parseInt(operationDiv.style.left, 10);
      const lastWidth = parseInt(operationDiv.style.width, 10);

      canvas.style.height = `${currentTop}px`;
      canvas.style.width = `${lastLeft + lastWidth + 250}px`;
      document.getElementById("detail-separator").style.width = canvas.style.width;

      // testsLaunchInterval is sorted
      let averageNodeLaunchInterval = {};
      let averageNodeLaunchIntervalCount = {};
      let averageLaunchInterval = 0.0;
      let averageLaunchIntervalCount = 0.0;

      for (let item of testsLaunchInterval) {
        averageNodeLaunchInterval[item.test.node] = (averageNodeLaunchInterval[item.test.node] || 0.0) + item.deltaInterval;
        averageNodeLaunchIntervalCount[item.test.node] = (averageNodeLaunchIntervalCount[item.test.node] || 0) + 1;

        averageLaunchInterval += item.deltaInterval;
        averageLaunchIntervalCount += 1;
      }

      let slowTestsLaunchInterval = testsLaunchInterval.filter(function (item) {
        return item.deltaInterval > 60;
      });

      let nodeUtilizationInterval = {};

      for (let test of tests) {
        const key = `${test.node}`;
        nodeUtilizationInterval[key] = (nodeUtilizationInterval[key] || 0) + test.endInterval - test.startInterval;
      }

      const executionDetailsDiv = document.getElementById("execution-details");
      if (Object.keys(nodeUtilizationInterval).length > 0) {
        var deviceUsageTitle = document.createElement('h2');
        deviceUsageTitle.innerText = `Device utilization time`;
        executionDetailsDiv.appendChild(deviceUsageTitle);

        for (let node of Object.keys(nodeUtilizationInterval).sort()) {
          var runnerCount = {};
          let testRunnedCount = 0
          for (let test of tests) {
            if (test.node == node) {
              runnerCount[test.runnerName] = true;
              testRunnedCount += 1;
            }
          }

          runnerCount = Object.keys(runnerCount).length
          const time = nodeUtilizationInterval[node] / runnerCount

          var itemDiv = document.createElement('div');
          const percentage = Math.trunc(100 * time / testOperationDuration);
          itemDiv.innerHTML = `<b>${node} &nbsp;&nbsp; <progress value="${percentage}" max="100"> ${percentage}% </progress>&nbsp;&nbsp;${testRunnedCount} tests executed in ${formatTime(time)} per node (${Math.trunc(100 * time / testOperationDuration)}%) using ${runnerCount} simulators</b><br /><br />`;
          executionDetailsDiv.appendChild(itemDiv);
        }
      }

      if (averageLaunchIntervalCount > 1) {
        var averageTestsLaunchIntervalTitle = document.createElement('h2');
        averageTestsLaunchIntervalTitle.innerText = `Average test launch intervals`;
        executionDetailsDiv.appendChild(averageTestsLaunchIntervalTitle);

        var itemDiv = document.createElement('div');
        itemDiv.innerHTML = `<b>${formatTime(averageLaunchInterval / averageLaunchIntervalCount)}</b>`;
        executionDetailsDiv.appendChild(itemDiv);

        var averageNodeTestsLaunchIntervalTitle = document.createElement('h2');
        averageNodeTestsLaunchIntervalTitle.innerText = `Average node test launch intervals`;
        executionDetailsDiv.appendChild(averageNodeTestsLaunchIntervalTitle);

        for (let node in averageNodeLaunchInterval) {
          const average = averageNodeLaunchInterval[node];
          const count = averageNodeLaunchIntervalCount[node];

          var itemDiv = document.createElement('div');
          itemDiv.innerHTML = `<b>${node} ${formatTime(average / count)}</b><br /><br />`;
          executionDetailsDiv.appendChild(itemDiv);
        }
      }

      if (slowTestsLaunchInterval.length > 0) {
        slowTestsLaunchInterval = slowTestsLaunchInterval.sort((a, b) => (a.deltaInterval < b.deltaInterval) ? 1 : -1);

        const executionDetailsDiv = document.getElementById("execution-details");

        var slowTestsLaunchIntervalTitle = document.createElement('h2');
        slowTestsLaunchIntervalTitle.innerText = "Slow test launch intervals";
        executionDetailsDiv.appendChild(slowTestsLaunchIntervalTitle);

        for (let item of slowTestsLaunchInterval) {
          var itemDiv = document.createElement('div');
          itemDiv.innerHTML = `<b>${item.test.node} ${item.test.runnerName} @${Math.trunc(item.previousTest.endInterval)}s</b><br />Waited ${formatTime(item.deltaInterval)} (${item.previousTest.suite}/${item.previousTest.name} -> ${item.test.suite}/${item.test.name})<br /><br />`;
          executionDetailsDiv.appendChild(itemDiv);
        }
      }
    </script>
    </body>
    </html>
    """
}
