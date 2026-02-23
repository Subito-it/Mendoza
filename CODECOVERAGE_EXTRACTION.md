# Code Coverage Extraction Analysis

## Overview

This document analyzes how intermediate/individual test coverage extraction works in Mendoza.

## Architecture

### During Test Execution (`TestRunnerOperation.swift`)

1. Each test creates a new `.profdata` file (created by xcodebuild)
2. After each test completes:
   - The new profdata file is identified (non-UUID named, since merged files use UUID names)
   - If individual coverage extraction is enabled, the new profdata is copied to a test-specific file
   - All profdata files are merged progressively to avoid slow final merge
3. In an async queue, individual test coverage JSON is generated from the isolated profdata
4. The JSON is saved with a test-specific filename: `{suite}-{name}-{startInterval}.json`

### How New Profdata Files Are Identified

The `CodeCoverageMerger` creates merged profdata files with UUID-based names (e.g., `550e8400-e29b-41d4-a716-446655440000.profdata`). Files created by xcodebuild have different naming patterns. By filtering out UUID-named files, we can identify the newly created profdata from the just-completed test.

### After All Tests Complete

**`TestCollectorOperation.swift`:**
1. Collects all `.profdata` files from all runners to the destination node
2. Also collects pre-generated individual coverage JSONs if `extractIndividualTestCoverage` is enabled

**`CodeCoverageCollectionOperation.swift`:**
1. Merges all collected `.profdata` files into a final combined profdata
2. Generates final coverage reports (JSON, HTML) from the combined profdata

## Why Progressive Merge Exists

The progressive merge was introduced to avoid a performance problem: merging all profdata files at the end of execution can take a very long time. By merging progressively during test execution, the final merge has much less work to do.

## Flow Diagram

```
Test completes → xcodebuild creates new.profdata
                     │
    ┌────────────────┴────────────────┐
    ↓                                 ↓
Copy new.profdata to              Merge all .profdata
{test}.profdata (isolated)        into combined.profdata
    ↓                                 ↓
Generate individual JSON          (keeps progressive merge
from {test}.profdata               working for final coverage)
    ↓
Clean up {test}.profdata
```
