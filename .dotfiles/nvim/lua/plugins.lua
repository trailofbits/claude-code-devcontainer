return {
	-- Treesitter: syntax highlighting + text objects
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		config = function()
			local ok, ts_configs = pcall(require, "nvim-treesitter.configs")
			if not ok then
				vim.schedule(function()
					vim.notify(
						"nvim-treesitter not available yet. Run :Lazy sync and restart Neovim.",
						vim.log.levels.WARN
					)
				end)
				return
			end

			ts_configs.setup({
				ensure_installed = {
					"bash", "go", "json", "lua", "markdown", "python",
					"toml", "typescript", "yaml",
				},
				highlight = { enable = true },
				indent = { enable = true },
			})
		end,
	},

	-- Telescope: fuzzy finder
	{
		"nvim-telescope/telescope.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		keys = {
			{ "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
			{ "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
			{ "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
			{ "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
		},
	},

	-- Git
	{ "tpope/vim-fugitive" },

	-- Commenting
	{
		"numToStr/Comment.nvim",
		config = function()
			require("Comment").setup()
		end,
	},

	-- Completion engine (required by minuet-ai)
	{
		"hrsh7th/nvim-cmp",
		dependencies = {
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
		},
		config = function()
			local cmp = require("cmp")
			cmp.setup({
				sources = cmp.config.sources({
					{ name = "minuet" },
					{ name = "path" },
				}, {
					{ name = "buffer" },
				}),
				mapping = cmp.mapping.preset.insert({
					["<C-Space>"] = cmp.mapping.complete(),
					["<CR>"] = cmp.mapping.confirm({ select = false }),
					["<C-e>"] = cmp.mapping.abort(),
					["<Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item()
						else
							fallback()
						end
					end, { "i", "s" }),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_prev_item()
						else
							fallback()
						end
					end, { "i", "s" }),
				}),
				performance = {
					debounce = 100,
				},
			})
		end,
	},

	-- Codex ghost-text autocomplete
	{
		"milanglacier/minuet-ai.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			local minuet_provider = vim.env.MINUET_PROVIDER or "openai"
			require("minuet").setup({
				provider = minuet_provider,
				provider_options = {
					claude = {
						api_key = os.getenv("ANTHROPIC_API_KEY"),
						model = "claude-sonnet-4-20250514",
					},
					openai = {
						api_key = os.getenv("OPENAI_API_KEY"),
						model = "gpt-5.3-codex",
					},
				},
			})
		end,
	},

	-- Claude Code IDE bridge
	{
		"coder/claudecode.nvim",
		config = function()
			require("claudecode").setup()
		end,
	},
}
