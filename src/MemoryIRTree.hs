module MemoryIRTree where

import MultiTree
import Data.Char (toLower)
import Semantics
import Transforms
import Data.Map as M hiding (map, foldl, filter, singleton)
import Data.IORef
import System.IO.Unsafe

counter = unsafePerformIO $ 
		 newIORef 0

increment i = unsafePerformIO $ do
	modifyIORef counter (+1)
	x <- readIORef counter
	return (x)
	


type LowIRTree = MultiTree IRNode
type VarBindings = M.Map String MemLoc

data Register = RAX | RBX | RCX | RDX | RSP | RBP | RSI | RDI | R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15 deriving (Eq, Enum)
regs = map show [RAX .. R15]

instance ValidMemLoc Register where
    toMemLoc = Reg

class Registerizable a where
    reg :: Register -> a
    isReg :: a -> Bool
    getReg :: a -> Maybe Register

instance Registerizable Register where
    reg x = x
    isReg = const True
    getReg x = Just x 

data MemLoc = Reg Register | BPOffset Int | Label String deriving (Eq)

instance Registerizable MemLoc where
    reg x = Reg x

    isReg (Reg _) = True
    isReg _ = False

    getReg (Reg x) = Just x
    getReg _ = Nothing
instance Show MemLoc where
	show (Reg r) = map toLower $ (show r)
	show (BPOffset i) = (show i)++"(%rbp)"
	show (Label str) = str

instance Show Register where
    show RAX = "%rax"
    show RBX = "%rbx"
    show RCX = "%rcx"
    show RDX = "%rdx"
    show RSP = "%rsp"
    show RBP = "%rbp"
    show RSI = "%rsi"
    show RDI = "%rdi"
    show R8 = "%r8"
    show R9 = "%r9"
    show R10 = "%r10"
    show R11 = "%r11"
    show R12 = "%r12"
    show R13 = "%r13"
    show R14 = "%r14"
    show R15 = "%r15"

class ValidMemLoc a where
    toMemLoc :: a -> MemLoc

instance ValidMemLoc MemLoc where
    toMemLoc = id

data IRNode = ProgL
            | MethodCallL Id
            | AndL
            | OrL
            | AddL
            | SubL
            | MulL
            | ModL
            | DivL
            | NotL
            | NegL
            | AssignPlusL
            | AssignMinusL
            | AssignL
            | NeqlL
            | EqlL
            | LtL
            | LteL
            | GtL
            | GteL
            | LocL MemLoc
            | DStrL String
            | DCharL Char
            | DIntL Int
            | DBoolL Bool
            | DBlockL
            | ReturnL
            | BreakL
            | ContinueL
            | IfL
            | ForL Id
            | WhileL
            | FDL FDType TypedId
            | CDL Id
            | PDL TypedId
            | MDL TypedId
     deriving (Show, Eq)

convertToLowIRTree :: SemanticTreeWithSymbols -> LowIRTree
convertToLowIRTree = convertToLowIRTree' . (fmap (\(_,x,_) -> x))

convertToLowIRTree' :: MultiTree STNode -> LowIRTree
convertToLowIRTree' (MT Prog forest) = (MT ProgL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (MethodCall x) forest) = (MT (MethodCallL x) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT And forest) = (MT AndL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Or forest) = (MT OrL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Add forest) = (MT AddL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Sub forest) = (MT SubL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Mul forest) = (MT MulL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Mod forest) = (MT ModL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Div forest) = (MT DivL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Not forest) = (MT NotL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Neg forest) = (MT NegL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT AssignPlus forest) = (MT AssignPlusL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT AssignMinus forest) = (MT AssignMinusL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Assign forest) = (MT AssignL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Neql forest) = (MT NeqlL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Eql forest) = (MT EqlL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Lt forest) = (MT LtL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Lte forest) = (MT LteL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Gt forest) = (MT GtL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Gte forest) = (MT GteL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (Loc i) forest) = (MT (undefined) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (DStr s) forest) = (MT (DStrL s) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (DChar c) forest) = (MT (DCharL c) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (DInt n) forest) = (MT (DIntL n) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (DBool b) forest) = (MT (DBoolL b) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT DBlock forest) = (MT DBlockL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Return forest) = (MT ReturnL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Break forest) = (MT BreakL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT Continue forest) = (MT ContinueL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT If forest) = (MT IfL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (For i) forest) = (MT (ForL i) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT While forest) = (MT WhileL (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (FD ftp ti) forest) = (MT (FDL ftp ti) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (CD i) forest) = (MT (CDL i) (map convertToLowIRTree' forest))
convertToLowIRTree' (MT (PD ti) forest) = (MT (PDL ti) (map convertToLowIRTree' forest))
convertToLowIRTree' node@(MT (MD ti) forest) = (MT (MDL ti) (map (fmap (fixLocations table)) forest))
    where table = getVarBindings' node
convertToLowIRTree' _ = undefined


fixLocations :: VarBindings -> STNode -> IRNode
fixLocations table (Loc i) = LocL $ (table ! idString i)
fixLocations _ Prog = ProgL
fixLocations _ (MethodCall i) = MethodCallL i
fixLocations _ And = AndL
fixLocations _ Or = OrL
fixLocations _ Add = AddL
fixLocations _ Sub = SubL
fixLocations _ Mul = MulL
fixLocations _ Mod = ModL
fixLocations _ Div = DivL
fixLocations _ Not = NotL
fixLocations _ Neg = NegL
fixLocations _ AssignPlus = AssignPlusL
fixLocations _ AssignMinus = AssignMinusL
fixLocations _ Assign = AssignL
fixLocations _ Neql = NeqlL
fixLocations _ Eql = EqlL
fixLocations _ Lt = LtL
fixLocations _ Lte = LteL
fixLocations _ Gt = GtL
fixLocations _ Gte = GteL
fixLocations _ (DStr s) = DStrL s
fixLocations _ (DChar c) = DCharL c
fixLocations _ (DInt n) = DIntL n
fixLocations _ (DBool b) = DBoolL b
fixLocations _ DBlock = DBlockL
fixLocations _ Return = ReturnL
fixLocations _ Break = BreakL
fixLocations _ Continue = ContinueL
fixLocations _ If = IfL
fixLocations _ (For i) = ForL i
fixLocations _ While = WhileL
fixLocations _ (FD fdt ti) = FDL fdt ti
fixLocations _ (CD i) = CDL i
fixLocations _ (PD ti) = PDL ti
fixLocations _ (MD ti) = MDL ti
fixLocations _ _ = undefined
 

-- Should only be called on a MD node.. will not play well when called at a higher level
-- bindings for parameters in order
-- parameters negative rbp offset, locals positive
paramBindings :: [MemLoc]
paramBindings = map reg [RDI, RSI, RDX, RCX, R8, R9] ++ map (BPOffset . (*(8))) [1..]
getVarBindings :: SemanticTreeWithSymbols -> VarBindings
getVarBindings = getVarBindings' . fmap second
    where second (_, x, _) = x

getVarBindings' :: MultiTree STNode -> VarBindings
getVarBindings' node = third $ foldl f (1, paramBindings, M.empty) $ listify node
    where f (n, (x:xs), bs) (PD (_, i)) = (n, xs, M.insert (idString i) x bs)
          f (n, xs, bs) (FD _ (_, i)) = (n+1, xs, M.insert (idString i) (BPOffset (-8*n)) bs)
          f acc _ = acc
          third (_,_,x) = x

testMethod :: MultiTree STNode
testMethod = MT (MD (IntType, mkId "fact")) chillens 
chillens = [ singleton (PD (IntType, mkId "n")),
    MT DBlock [ 
        singleton (FD Single (BoolType, mkId "b")),
        singleton (FD Single (IntType, mkId "a")),
        singleton (Loc $ mkId "n")
        ]
        ]
        
