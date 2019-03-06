import Foundation
import Bariloche

let parser = Bariloche(command: RootCommand())
let result = parser.parse()
