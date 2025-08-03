module dynexus_forge::token_factory {

    use std::error;
    use std::option;
    use std::signer::address_of;
    use std::string::String;
    use std::vector;
    use aptos_std::table;
    use aptos_std::table::Table;
    use aptos_framework::event;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, MintRef, TransferRef, BurnRef};
    use aptos_framework::object;
    use aptos_framework::object::{Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    #[test_only]
    use aptos_framework::genesis;


    //
    // Constants
    //
    /// Contract addresss
    const CA: address = @dynexus_forge;
    /// Token creation seed
    const TOKEN_SEED: vector<u8> = b"DYNEXUS";
    /// Token factory object creation seed
    const TOKEN_FACTORY_OBJECT_SEED: vector<u8> = b"DYNEXUS_FORGE_OWNER";
    /// Max symbol length
    const MAX_SYMBOL_LENGTH: u8 = 2;

    //
    // Errors
    //
    /// Token already exists in the registry.
    const E_TOKEN_ALREADY_EXISTS: u64 = 1;

    /// Provided parameters are invalid.
    const E_INVALID_PARAMETERS: u64 = 2;

    /// User has insufficient balance for the operation.
    const E_INSUFFICIENT_BALANCE: u64 = 3;

    /// Requested swap pair or route was not found.
    const E_SWAP_NOT_FOUND: u64 = 4;

    /// Swap request has expired and is no longer valid.
    const E_SWAP_EXPIRED: u64 = 5;

    /// User is not the owner and is not authorized to perform this action.
    const E_NOT_AN_OWNER: u64 = 6;

    /// Token not exists in the registry.
    const E_TOKEN_NOT_EXISTS: u64 = 7;

    /// Token factory not initialized yet..
    const E_REGISTRY_NOT_EXISTS: u64 = 8;

    //
    // Structs
    //

    struct TokenInfo has store, copy, drop {
        name: String,
        symbol: String,
        decimals: u8,
        token_address: address,
        creator: address,
        icon_uri: String,
        project_uri: String,
        total_supply: u64,
        created_at: u64
    }

    struct UserTokens has key, store {
        created_tokens: vector<address>
    }

    struct TokenRegistry has key {
        // Global token registry
        tokens: Table<address, TokenInfo>,
        total_list: vector<address>,
        tokens_seeds: Table<vector<u8>, address>,

        // User management
        user_tokens: Table<address, UserTokens>,

        // Statistics
        total_users: u64,

        // Admin controls
        admin: address,
        plateform_fee_rate: u64,

        // extending object signer
        extend_ref: ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManageFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        creator: address
    }

    struct TokenList has copy, drop {
        name: String,
        symbol: String,
        token_address: address
    }

    //
    // Events
    //

    #[event]
    struct TokenCreated has drop, store {
        creator: address,
        token_address: address,
        inital_supply: u64,
        timestamp: u64
    }

    #[event]
    struct TokenTransfer has drop, store {
        from: address,
        to: address,
        token_address: address,
        amount: u64,
        timestamp: u64
    }

    //
    // Inttialize Function
    //
    /// Initializes the Token Factory module
    ///
    /// # Parameters
    /// - `admin`: signer of the admin deploying the token factory
    fun init_module(admin: &signer) {
        let admin_addr = address_of(admin);
        let constructor_ref =
            &object::create_named_object(admin, TOKEN_FACTORY_OBJECT_SEED);
        let obj_signer = &object::generate_signer(constructor_ref);
        let extend_ref = object::generate_extend_ref(constructor_ref);

        move_to(
            obj_signer,
            TokenRegistry {
                admin: admin_addr,
                tokens: table::new(),
                tokens_seeds: table::new(),
                user_tokens: table::new(),
                total_list: vector::empty<address>(),
                total_users: 0,
                plateform_fee_rate: 100, // 1% default,
                extend_ref
            }
        );
    }

    //
    // Token Creation & Management
    //

    /// Creates a custom fungible token in the DYNA ecosystem.
    ///
    /// # Parameters
    /// - `creator`: signer of the token creator
    /// - `name`: Full name of the token
    /// - `symbol`: Short symbol (max 2 chars)
    /// - `decimals`: Decimal precision (max 18)
    /// - `inital_supply`: Initial amount of tokens to mint to creator
    /// - `icon_uri`: Link to token icon
    /// - `project_uri`: Project website or metadata link
    ///
    /// # Returns
    /// - `(creator_address, token_address)`
    ///
    /// # Aborts With
    /// - `E_SYMBOL_TOO_LONG` if symbol > MAX_SYMBOL_LENGTH
    /// - `E_TOKEN_ALREADY_EXISTS` if token with same name/symbol exists
    /// - `E_INVALID_PARAMETERS` for invalid decimals or URIs
    public fun create_token(
        creator: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        inital_supply: u64,
        icon_uri: String,
        project_uri: String
    ) acquires TokenRegistry, ManageFungibleAsset {

        let creator_addr = address_of(creator);

        let registry_addr = get_token_factory_object_addr();
        assert_token_factory(registry_addr);
        let registry = borrow_global_mut<TokenRegistry>(registry_addr);

        let token_seed = create_token_seed(&name, &symbol);
        assert_duplicate_token_by_seed(&registry.tokens_seeds, &token_seed);

        validate_token_parameters(decimals, &icon_uri, &project_uri);

        let constuctor_ref = object::create_named_object(creator, token_seed);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constuctor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constuctor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constuctor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constuctor_ref);
        let token_signer = object::generate_signer(&constuctor_ref);
        let token_address = address_of(&token_signer);

        move_to(
            &token_signer,
            ManageFungibleAsset { mint_ref, burn_ref, transfer_ref, creator: creator_addr }
        );

        let token_info = TokenInfo {
            name,
            symbol,
            decimals,
            token_address,
            creator: creator_addr,
            icon_uri,
            project_uri,
            total_supply: inital_supply,
            created_at: timestamp::now_seconds()
        };

        registry.tokens.add(token_address, token_info);
        registry.tokens_seeds.add(token_seed, token_address);
        registry.total_list.push_back(token_address);

        if (!registry.user_tokens.contains(creator_addr)) {
            registry.user_tokens.add(
                creator_addr, UserTokens { created_tokens: vector::empty() }
            );

            registry.total_users += 1;
        };

        let user_tokens = registry.user_tokens.borrow_mut(creator_addr);
        user_tokens.created_tokens.push_back(token_address);

        if (inital_supply > 0) {
            let manage_ref = borrow_global<ManageFungibleAsset>(token_address);
            let fa = fungible_asset::mint(&manage_ref.mint_ref, inital_supply);
            primary_fungible_store::deposit(creator_addr, fa);
        };

        event::emit(
            TokenCreated {
                creator: creator_addr,
                token_address,
                inital_supply,
                timestamp: timestamp::now_seconds()
            }
        );

    }

    /// Mints additional supply of a DYNA-based token to a user
    ///
    /// # Parameters
    /// - `owner`: signer of token owner/creator
    /// - `to`: address to receive minted tokens
    /// - `token_address`: address of the token to mint
    /// - `amount`: quantity to mint
    ///
    /// # Aborts With
    /// - `E_NOT_AN_OWNER` if caller is not token creator
    public fun mint_token(
        owner: &signer,
        to: address,
        token_address: address,
        amount: u64
    ) acquires ManageFungibleAsset, TokenRegistry {
        let owner_addr = address_of(owner);
        assert_is_token_owner(owner_addr, token_address);

        let asset = get_token_metadata(token_address);

        authorized_metadata_refs(owner_addr, asset);
        let metadata =
            borrow_global_mut<ManageFungibleAsset>(object::object_address(&asset));
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);

        let token = fungible_asset::mint(&metadata.mint_ref, amount);
        fungible_asset::deposit_with_ref(&metadata.transfer_ref, to_wallet, token);
    }

    /// Transfers a DYNA-based token between two users
    ///
    /// # Parameters
    /// - `from`: signer initiating the transfer
    /// - `to`: recipient address
    /// - `token_address`: address of the token being transferred
    /// - `amount`: amount to transfer
    ///
    /// # Aborts With
    /// - `E_INSUFFICIENT_BALANCE` if balance is insufficient
    public entry fun transfer_token(
        from: &signer,
        to: address,
        token_address: address,
        amount: u64
    ){
        let from_addr = address_of(from);
        assert_sufficinet_balance(from_addr, amount, token_address);
        primary_fungible_store::transfer(from, object::address_to_object<Metadata>(token_address), to ,amount);

        event::emit(
            TokenTransfer {
                from: from_addr,
                to,
                token_address,
                amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    //
    // Helper Functions
    //

    /// Validate token parameters
    fun validate_token_parameters(
        decimals: u8, icon_uri: &String, project_uri: &String
    ) {
        assert!(decimals <= 18, error::invalid_argument(E_INVALID_PARAMETERS));
        assert!(icon_uri.length() <= 512, error::invalid_argument(E_INVALID_PARAMETERS));
        assert!(
            project_uri.length() <= 512, error::invalid_argument(E_INVALID_PARAMETERS)
        );
    }

    /// Create token seed
    fun create_token_seed(name: &String, symbol: &String): vector<u8> {
        let seed = vector::empty<u8>();
        seed.append(*name.bytes());
        seed.append(*symbol.bytes());

        seed
    }

    fun is_token_exist(table: &Table<address, TokenInfo>, addr: &address): bool {
        table.contains(*addr)
    }

    /// Generate token object creation seed
    fun generate_token_object_seed(suffix: vector<u8>): vector<u8> {
        let seed = TOKEN_SEED;
        seed.append(suffix);
        seed
    }

    /// Validate the token authority
    fun authorized_metadata_refs(
        owner_addr: address, asset: Object<Metadata>
    ) {
        assert_is_objet_owner<Metadata>(owner_addr, asset);
    }

    /// Checks token is registed or not
    fun is_token_registered(token: address): bool acquires TokenRegistry {
        let res_addr = get_token_factory_object_addr();
        let registry = borrow_global<TokenRegistry>(res_addr);
        registry.tokens.contains(token)
    }

    fun get_token_factory_object_addr(): address {
        object::create_object_address(&CA, TOKEN_FACTORY_OBJECT_SEED)
    }

    public fun get_token_metadata(
        token_addr: address
    ): object::Object<Metadata> acquires TokenRegistry {
        let registry_addr = get_token_factory_object_addr();
        assert_token_factory(registry_addr);

        let registry = borrow_global<TokenRegistry>(registry_addr);
        assert!(registry.tokens.contains(token_addr), E_TOKEN_NOT_EXISTS);

        let token_ref = registry.tokens.borrow(token_addr); // &TokenList
        let seed = create_token_seed(&token_ref.name, &token_ref.symbol);

        let asset_addr = create_token_object_addr(token_ref.creator, seed);
        object::address_to_object<Metadata>(asset_addr)
    }

    /// Get the token object address
    public fun create_token_object_addr(
        user_addr: address, seed: vector<u8>
    ): address {
        object::create_object_address(&user_addr, seed)
    }

    public fun get_balance(
        user_address: address, token_address: address
    ): u64 {
        primary_fungible_store::balance(user_address, object::address_to_object<Metadata>(token_address))
    }

    //
    // View functions
    //

    #[view]
    public fun get_tokens(): vector<TokenList> acquires TokenRegistry {
        let registry_addr = get_token_factory_object_addr();
        assert_token_factory(registry_addr);
        let registry = borrow_global<TokenRegistry>(registry_addr);

        let tokens = &registry.tokens;

        let res = vector::empty<TokenList>();
        let token_addresses = registry.total_list;

        let i = 0;
        while (i < token_addresses.length()) {
            let addr = token_addresses.borrow(i);
            if (tokens.contains(*addr)) {
                let token = tokens.borrow(*addr);
                res.push_back(
                    TokenList {
                        name: token.name,
                        symbol: token.symbol,
                        token_address: *addr
                    }
                );
            };
            i += 1;
        };

        res
    }

    //
    // Asserts
    //

    /// Assert if token is not registred
    public fun assert_registered(token: address) acquires TokenRegistry {
        assert!(is_token_registered(token), E_TOKEN_NOT_EXISTS);
    }

    fun assert_token_factory(addr: address) {
        assert!(exists<TokenRegistry>(addr), E_REGISTRY_NOT_EXISTS);
    }

    /// Assert that token is unique by seed
    fun assert_duplicate_token_by_seed(
        table: &Table<vector<u8>, address>, seed: &vector<u8>
    ) {
        assert!(!table.contains(*seed), error::already_exists(E_TOKEN_ALREADY_EXISTS))
    }

    /// Assert that token is unique
    fun assert_duplicate_token_by_addr(
        table: &Table<address, TokenInfo>, addr: &address
    ) {
        assert!(
            !is_token_exist(table, addr),
            error::already_exists(E_TOKEN_ALREADY_EXISTS)
        )
    }

    /// Assert that balance is exists
    fun assert_sufficinet_balance(
        addr: address, amount: u64, token_address: address
    ) {
        assert!(
            get_balance(addr, token_address) >= amount, error::aborted(E_INSUFFICIENT_BALANCE)
        );
    }

    /// Assert if user is not a owner of object
    public fun assert_is_objet_owner<T: key>(
        owner_addr: address, asset: Object<T>
    ) {
        assert!(object::is_owner<T>(asset, owner_addr), E_NOT_AN_OWNER);
    }

    /// Assert if user is not a owner of token
    public fun assert_is_token_owner(
        owner_addr: address, token_addr: address
    ) acquires TokenRegistry {
        let registry_addr = get_token_factory_object_addr();
        assert_token_factory(registry_addr);
        let registry = borrow_global<TokenRegistry>(registry_addr);

        assert!(registry.user_tokens.contains(owner_addr), E_NOT_AN_OWNER);
        assert!(
            registry.user_tokens.borrow(owner_addr).created_tokens.contains(&token_addr),
            E_NOT_AN_OWNER
        );
    }

    //
    // Test functions
    //
    #[test_only]
    public fun initalize_token_factory_with_out_genesis(admin: &signer) {
        init_module(admin)
    }

    #[test_only]
    public fun initalize_token_factory(admin: &signer) {
        genesis::setup();
        init_module(admin)
    }

    #[test_only]
    public fun create_test_token(
        creator: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        inital_supply: u64,
        icon_uri: String,
        project_uri: String,
        index: u64
    ): (String, String, address) acquires TokenRegistry, ManageFungibleAsset {
        create_token(
            creator,
            name,
            symbol,
            decimals,
            inital_supply,
            icon_uri,
            project_uri
        );

        let tokens =get_tokens();
        let token = tokens[index];

        (token.name, token.symbol, token.token_address)
    }

    #[test_only]
    public fun get_token_balance(owner: &signer, token_add: address): u64 acquires TokenRegistry {
        let asset = get_token_metadata(token_add);
        let wallet =
            primary_fungible_store::ensure_primary_store_exists(
                address_of(owner), asset
            );
        fungible_asset::balance(wallet)
    }
}