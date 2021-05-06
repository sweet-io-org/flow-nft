/*
    Description: Digital Collectible contract for Sweet Inc.
    The token contains a minimal amount of metadata (name, URI, sha256 hash, sequence number).
    The full metadata, with images, media, rights and restrictions, is documented here:
    https://github.com/sweet-io-org/nft-schema

    Each token is part of a Series, with a preset quantity.  The token URI will be the series URI
    plus an additional path element, for example:
    
       Series URI: https://foo.bar/series/abc123
       Token URI:  https://foo.bar/series/abc123/52   (for sequence-number 52)

    The URI of the token or series MAY be resolvable to an HTTP object.  That object should be
    requested with an "Accept: application/json" request header.  The Document it
    returns must have the same sha256 set as a Token property.

    The Owner of a token MAY set a Preferred URL, and update this property of the NFT.
    If a Preferred URL is set, then it defines the preferred URL for retrieving the
    Token Document, and any of the assets associated for it.  For example, if the
    Token URL is https://foo.bar/series/abc123/52, and the Token Owner sets a
    Preferred URL of https://my.domain.com/foo/series-abc123-no-52, then the URI
    should be substituted with the Preferred URL for retrieving the Token Document and
    all assets defined within the token document.  For example:

    https://foo.bar/series/abc123/52  -> https://my.domain.com/foo/series-abc123-no-52
    https://foo.bar/series/abc123/52/image/front.png  -> https://my.domain.com/foo/series-abc123-no-52/image/front.png

    URLs within the document that don't contain the URI are not changed, for example the following link is unchanged:
   
    https://collectible.sweet.io/static/terms-and-conditions-mar2021.txt -> https://collectible.sweet.io/static/terms-and-conditions-mar2021.txt

    authors: Ken Ellis ken@sweet.io

*/

import NonFungibleToken from 0x1

pub contract SweetDC: NonFungibleToken {

    // Emitted when the contract is created
    pub event ContractInitialized()

    // Emitted when a token is minted
    pub event Minted(tokenID: UInt64, tokenURI: String, seriesURI: String, sequenceNumber: UInt32)

    // Emitted when a token is withdrawn from a Collection
    pub event Withdraw(id: UInt64, from: Address?)
    // Emitted when a token is deposited into a Collection
    pub event Deposit(id: UInt64, to: Address?)

    // Emitted when a Token is destroyed
    pub event TokenDestroyed(id: UInt64)
    
    // Emitted when a new Series is defined
    pub event SeriesCreated(seriesURI: String, maxSupply: UInt32, sha256: String, name: String)

    // Named paths
    pub let SweetDCStoragePath: StoragePath
    pub let SweetDCAdminStoragePath: StoragePath
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath

    // JSON Schema definition for the document associated with the Token
    pub let DocumentSchema: String


    // -----------------------------------------------------------------------
    // contract-level fields.
    // These contain actual values that are stored in the smart contract.
    // -----------------------------------------------------------------------

    // dictionary of series URI -> Resource
    access(self) var series: @{String: Series}

    // The total number of SweetDC NFTs that have been created
    // Because NFTs can be destroyed, it doesn't necessarily mean that this
    // reflects the total number of NFTs in existence, just the number that
    // have been minted to date. 
    pub var totalSupply: UInt64

    // -----------------------------------------------------------------------
    // contract-level Composite Type definitions
    // -----------------------------------------------------------------------
    // These are just *definitions* for Types that this contract
    // and other accounts can use. These definitions do not contain
    // actual stored values, but an instance (or object) of one of these Types
    // can be created by this contract that contains stored values.
    // -----------------------------------------------------------------------

    // Data to describe a series, consisting of a maximum supply, a name,
    // and a sha256 hash of the series document stored off-chain
    pub struct SeriesData {
        // hash for the series document
        pub let sha256: String
        // total number that can ever be minted
        pub let maxSupply: UInt32
        // name
        pub let name: String
        // URI, will be globally unique
        pub let seriesURI: String
        
        init(seriesURI: String, name: String, sha256: String, maxSupply: UInt32) {
            self.seriesURI = seriesURI
            self.name = name
            self.sha256 = sha256
            self.maxSupply = maxSupply
        }
    }

    // Metadata for a Token
    pub struct TokenData {

        // The ID of the Series that the Token comes from
        pub let seriesURI: String
        // Resource identifier for the extended document representing this token
        pub let tokenURI: String
        // sha256 hash of the document representing this token
        pub let sha256: String
        // sequence number of this token, starting at 1
        pub let sequenceNumber: UInt32
        // name of the token
        pub let name: String

        init(seriesURI: String, tokenURI: String, sha256: String, name: String, sequenceNumber: UInt32) {
            self.seriesURI = seriesURI
            self.tokenURI = tokenURI
            self.sha256 = sha256
            self.sequenceNumber = sequenceNumber
            self.name = name
        }
    }

    
    // -----------------------------------------------------------------------
    // resource definitions
    // -----------------------------------------------------------------------


    // Series resource,  SeriesData, and the next sequence
    // number used when minting Tokens belonging to the Series.  Sequence numbers
    // start at 1 and end with maxSupply
    pub resource Series {
        pub var nextSequenceNumber: UInt32
        pub let data: SeriesData     

        init(maxSupply: UInt32, seriesURI: String, sha256: String, name: String) {
            self.data = SeriesData(seriesURI: seriesURI, name: name, sha256: sha256, maxSupply: maxSupply)
            self.nextSequenceNumber = (1 as UInt32)
        }

        // Returns: The NFT that was minted
        pub fun mintToken(sha256: String, name: String): @NFT {
            pre {
                self.nextSequenceNumber <= self.data.maxSupply: "max supply reached"
            }
            // note that since seriesURIs are enforced to be globally unique by the contract,
            // this tokenURI will also be globally unique
            let tokenURI = self.data.seriesURI.concat("/").concat(self.nextSequenceNumber.toString())
            let newToken: @NFT <- create NFT(seriesURI: self.data.seriesURI,
                                             tokenURI: tokenURI,
                                             sha256: sha256,
                                             name: name,
                                             sequenceNumber: self.nextSequenceNumber)
            self.nextSequenceNumber = self.nextSequenceNumber + (1 as UInt32)
            return <-newToken
        }
    }

    // The resource that represents the NFT, containing the token metadata, and the URI of the 

    pub resource NFT: NonFungibleToken.INFT {

        // Global unique token ID
        pub let id: UInt64
        // Struct of Token metadata
        pub let data: TokenData
        // the preferred URL where token can be found, updatable by owner
        pub var preferredURL: String

        init(seriesURI: String, tokenURI: String, sha256: String, name: String, sequenceNumber: UInt32) {
            // Increment the global Token IDs
            SweetDC.totalSupply = SweetDC.totalSupply + (1 as UInt64)
            self.id = SweetDC.totalSupply
            // url is initialized to the URI it was originally minted at
            self.preferredURL = tokenURI
            // Set the metadata struct
            self.data = TokenData(seriesURI: seriesURI, tokenURI: tokenURI, 
              sha256: sha256, name: name, sequenceNumber: sequenceNumber)
            emit Minted(tokenID: self.id, tokenURI: tokenURI, seriesURI: seriesURI, sequenceNumber: sequenceNumber)
        }

        pub fun setPreferredURL(preferredURL: String) {
            self.preferredURL = preferredURL
        }

        // If the Token is destroyed, emit an event to indicate 
        // to outside ovbservers that it has been destroyed
        destroy() {
            emit TokenDestroyed(id: self.id)
        }
    }

    // Admin is a special authorization resource that 
    // allows the owner to perform important functions to modify the 
    // various aspects of the Plays, Sets, and Tokens
    //
    pub resource Admin {

        // creates a new Series, and stores it in the Series dictionary
        pub fun createSeries(maxSupply: UInt32, seriesURI: String, sha256: String, name: String) {
            // series URIs must be unique
            pre {
                SweetDC.series[seriesURI] == nil: "series uri already used"
            }
            var newSeries <- create Series(maxSupply: maxSupply, seriesURI: seriesURI, sha256: sha256, name: name)
            // Store it in the contract storage
            SweetDC.series[seriesURI] <-! newSeries
            emit SeriesCreated(seriesURI: seriesURI, maxSupply: maxSupply, sha256: sha256, name: name)
        }

        // borrowSeries returns a reference to the Series in the SweetDC 
        // contract so that the admin can call methods on it
        //
        // Parameters: seriesURI: The URI of the Series that you want to
        // get a reference to
        //
        // Returns: A reference to the Series with all of the fields
        // and methods exposed
        //
        pub fun borrowSeries(seriesURI: String): &Series {
            pre {
                SweetDC.series[seriesURI] != nil: "series doesn't exist"
            }
            
            // Get a reference to the Series and return it
            // use `&` to indicate the reference to the object and type
            return &SweetDC.series[seriesURI] as &Series
        }

        // createNewAdmin creates a new Admin resource
        //
        pub fun createNewAdmin(): @Admin {
            return <-create Admin()
        }
    }

    // This is the interface that users can cast their Token Collection as
    // to allow others to deposit Tokens into their Collection. It also allows for reading
    // the IDs of Tokens in the Collection.
    pub resource interface TokenCollectionPublic {
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun batchDeposit(tokens: @NonFungibleToken.Collection)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowToken(id: UInt64): &SweetDC.NFT? {
            // If the result isn't nil, the id of the returned reference
            // should be the same as the argument to the function
            post {
                (result == nil) || (result?.id == id): 
                    "Cannot borrow Token reference: The ID of the returned reference is incorrect"
            }
        }
        pub fun borrowTokenByURI(tokenURI: String) : &SweetDC.NFT? {
            post {
                (result == nil) || (result?.data?.tokenURI == tokenURI):
                    "Cannot borrow Token reference: The URI of the returned reference is incorrect"
            }
        }
        pub fun getTokenPreferredURL(id: UInt64): String?
        pub fun lookupTokenURI(tokenURI: String): UInt64?
    }

    // Collection is a resource that every user who owns NFTs 
    // will store in their account to manage their NFTS
    pub resource Collection: TokenCollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic { 
        // Dictionary of Token conforming tokens
        // NFT is a resource type with a UInt64 ID field
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}
        pub var tokenIDByURI: {String: UInt64}

        init() {
            self.ownedNFTs <- {}
            self.tokenIDByURI = {}
        }

        pub fun getTokenPreferredURL(id: UInt64): String? {
            let token = self.borrowToken(id: id) ?? panic("missing NFT")
            return token.preferredURL
        }

        pub fun lookupTokenURI(tokenURI: String): UInt64? {
            return self.tokenIDByURI[tokenURI]
        }

        pub fun changeTokenPreferredURL(id:UInt64, preferredURL: String) {
            let token <- self.ownedNFTs.remove(key: id) ?? panic("missing NFT")
            let sweetToken <- token as! @SweetDC.NFT
            sweetToken.setPreferredURL(preferredURL: preferredURL)
            self.ownedNFTs[id] <-! sweetToken
        }

        // withdraw removes an Token from the Collection and moves it to the caller
        //
        // Parameters: withdrawID: The ID of the NFT 
        // that is to be removed from the Collection
        //
        // returns: @NonFungibleToken.NFT the token that was withdrawn
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            // Remove the nft from the Collection
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")
            let sweetToken <- token as! @SweetDC.NFT
            self.tokenIDByURI.remove(key: sweetToken.data.tokenURI)
            let tok2 <- sweetToken as! @NonFungibleToken.NFT
            return <-tok2
        }

        // batchWithdraw withdraws multiple tokens and returns them as a Collection
        //
        // Parameters: ids: An array of IDs to withdraw
        //
        // Returns: @NonFungibleToken.Collection: A collection that contains
        //                                        the withdrawn moments
        //
        pub fun batchWithdraw(ids: [UInt64]): @NonFungibleToken.Collection {
            // Create a new empty Collection
            var batchCollection <- create Collection()
            
            // Iterate through the ids and withdraw them from the Collection
            for id in ids {
                batchCollection.deposit(token: <-self.withdraw(withdrawID: id))
            }
            
            // Return the withdrawn tokens
            return <-batchCollection
        }

        // deposit takes a Token and adds it to the Collections dictionary
        //
        // Paramters: token: the NFT to be deposited in the collection
        //
        pub fun deposit(token: @NonFungibleToken.NFT) {
            
            // Cast the deposited token as a SweetDC NFT to make sure
            // it is the correct type
            let token <- token as! @SweetDC.NFT

            // Get the token's ID
            let id = token.id
            self.tokenIDByURI[token.data.tokenURI] = id
            // Add the new token to the dictionary
            let oldToken <- self.ownedNFTs[id] <- token
            // Only emit a deposit event if the Collection 
            // is in an account's storage
            if self.owner?.address != nil {
                emit Deposit(id: id, to: self.owner?.address)
            }
            
            // Destroy the empty old token that was "removed"
            destroy oldToken
        }

        // batchDeposit takes a Collection object as an argument
        // and deposits each contained NFT into this Collection
        pub fun batchDeposit(tokens: @NonFungibleToken.Collection) {

            // Get an array of the IDs to be deposited
            let keys = tokens.getIDs()

            // Iterate through the keys in the collection and deposit each one
            for key in keys {
                self.deposit(token: <-tokens.withdraw(withdrawID: key))
            }

            // Destroy the empty Collection
            destroy tokens
        }

        // getIDs returns an array of the IDs that are in the Collection
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // borrowNFT Returns a borrowed reference to a Token in the Collection
        // so that the caller can read its ID
        //
        // Parameters: id: The ID of the NFT to get the reference for
        //
        // Returns: A reference to the NFT
        //
        // Note: This only allows the caller to read the ID of the NFT,
        // not any SweetDC specific data. Please use borrowToken to 
        // read Token data.
        //
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        // borrowToken returns a borrowed reference to a Token
        // so that the caller can read data and call methods from it.
        //
        // Parameters: id: The ID of the NFT to get the reference for
        //
        // Returns: A reference to the NFT
        pub fun borrowToken(id: UInt64): &SweetDC.NFT? {
            if self.ownedNFTs[id] != nil {
                let ref = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
                return ref as! &SweetDC.NFT
            } else {
                return nil
            }
        }

        // borrowTokenByURI returns a borrowed reference to a Token
        // so that the caller can read data and call methods from it.
        //
        // Parameters: tokenURI: The URI of the NFT to get the reference for
        //
        // Returns: A reference to the NFT
        pub fun borrowTokenByURI(tokenURI: String): &SweetDC.NFT? {
            let tokenID = self.tokenIDByURI[tokenURI] 
            if tokenID != nil {
                let ref = &self.ownedNFTs[tokenID!] as auth &NonFungibleToken.NFT
                return ref as! &SweetDC.NFT
            } else {
                return nil
            }
        }

        // If a transaction destroys the Collection object,
        // All the NFTs contained within are also destroyed!
        destroy() {
            destroy self.ownedNFTs
        }
    }

    // -----------------------------------------------------------------------
    // SweetDC contract-level function definitions
    // -----------------------------------------------------------------------

    // createEmptyCollection creates a new, empty Collection object so that
    // a user can store it in their account storage.
    // Once they have a Collection in their storage, they are able to receive
    // Tokens in transactions.
    //
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        return <-create SweetDC.Collection()
    }

    pub fun getSeriesURIs(): [String] {
        return SweetDC.series.keys
    }

    pub fun getSeriesData(seriesURI: String): SeriesData? {
        return SweetDC.series[seriesURI]?.data
    }

    // fetch
    // Get a reference to a KittyItem from an account's Collection, if available.
    // If an account does not have a KittyItems.Collection, panic.
    // If it has a collection but does not contain the itemID, return nil.
    // If it has a collection and that collection contains the itemID, return a reference to that.
    //
    pub fun fetch(_ from: Address, tokenURI: String): &SweetDC.NFT? {
        let collection = getAccount(from)
            .getCapability(SweetDC.CollectionPublicPath)
            .borrow<&SweetDC.Collection{SweetDC.TokenCollectionPublic}>()
            ?? panic("Couldn't get collection")
        // We trust SweetDC.Collection.borowTokenByURI to get the correct itemID
        // (it checks it before returning it).
        return collection.borrowTokenByURI(tokenURI: tokenURI)
    }        

    // -----------------------------------------------------------------------
    // SweetDC initialization function
    // -----------------------------------------------------------------------
    //
    init() {
        // Initialize contract fields
        self.totalSupply = 0
        self.series <- {}
        self.SweetDCStoragePath = /storage/SweetDCTokens
        self.CollectionStoragePath = /storage/SweetDCCollection
        self.CollectionPublicPath = /public/SweetDCCollection
        self.SweetDCAdminStoragePath = /storage/SweetDCAdmin
        self.DocumentSchema = "https://collectible.sweet.io/schema/token-1.0"

        // Put a new Collection in storage
        self.account.save<@Collection>(<- create Collection(), to: self.SweetDCStoragePath)

        // Create a public capability for the Collection
        self.account.link<&{TokenCollectionPublic}>(self.CollectionPublicPath, target: self.CollectionStoragePath)

        // Put the Admin minter in storage
        self.account.save<@Admin>(<- create Admin(), to: self.SweetDCAdminStoragePath)

        emit ContractInitialized()
    }
}
