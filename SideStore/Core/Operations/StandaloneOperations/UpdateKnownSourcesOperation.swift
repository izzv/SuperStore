//
//  UpdateKnownSourcesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 4/13/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

class UpdateKnownSourcesOperation: OperationLogging
{
    func execute() async throws -> ([KnownSource], [KnownSource])
    {
        let sourceURL = AppConstants.Sources.sideStoreCommunitySourceURL
        let defaultSources = [
            KnownSource(
                identifier: try Source.sourceID(from: sourceURL),
                sourceURL: sourceURL,
                bundleIDs: nil
            )
        ]

        UserDefaults.standard.recommendedSources = defaultSources
        UserDefaults.standard.blockedSources = []
        UserDefaults.standard.defaultSourceIDs = defaultSources.map { $0.identifier }

        return (defaultSources, [])
    }
}
