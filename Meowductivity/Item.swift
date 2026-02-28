//
//  Item.swift
//  Meowductivity
//
//  Created by Amirreza Ghiassian on 2026-02-28.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
