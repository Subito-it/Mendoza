import Bariloche
import Foundation

setbuf(__stdoutp, nil)

let parser = Bariloche(command: RootCommand())
let result = parser.parse()
