//
//  ContentBlockerRulesSourceManager.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import WebKit
import TrackerRadarKit

extension ContentBlockerRulesManager {
    
    final class InitialCompilationTask {
        
        struct CachedRulesList {
            let name: String
            let rulesList: WKContentRuleList
            let tds: TrackerData
            let rulesIdentifier: ContentBlockerRulesIdentifier
        }
        
        private let sourceRules: [ContentBlockerRulesList]
        private let lastCompiledRules: [LastCompiledRules]
        
        init(sourceRules: [ContentBlockerRulesList], lastCompiledRules: [LastCompiledRules]) {
            self.sourceRules = sourceRules
            self.lastCompiledRules = lastCompiledRules
        }

        func lookupCachedRulesLists() async throws -> [CachedRulesList] {
            let sourceRulesNames = sourceRules.map { $0.name }
            let filteredBySourceLastCompiledRules = lastCompiledRules.filter { sourceRulesNames.contains($0.name) }

            var result: [CachedRulesList] = []
            for rules in filteredBySourceLastCompiledRules {
                guard let ruleList = try await Task(operation: { @MainActor in
                    try await WKContentRuleListStore.default().contentRuleList(forIdentifier: rules.identifier.stringValue)
                }).value else { throw WKError(.contentRuleListStoreLookUpFailed) }

                result.append(CachedRulesList(name: rules.name,
                                              rulesList: ruleList,
                                              tds: rules.trackerData,
                                              rulesIdentifier: rules.identifier))
            }
            return result
        }

    }
}
